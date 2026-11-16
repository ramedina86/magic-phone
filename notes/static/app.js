const form = document.querySelector('#composer');
const input = document.querySelector('#note-text');
const grid = document.querySelector('#notes');
const feedback = document.querySelector('#feedback');
const save = document.querySelector('#save-button');
const more = document.querySelector('#load-more');
const dialog = document.querySelector('#delete-dialog');
let notes = [];
let total = 0;
let pendingDelete = null;
let loading = false;

function message(text, error = false) {
  feedback.textContent = text;
  feedback.classList.toggle('error', error);
}
async function api(path, options = {}) {
  const response = await fetch(path, { ...options, headers: { 'Content-Type': 'application/json', ...options.headers } });
  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    throw new Error(body.error || 'Couldn’t save that change. Please try again.');
  }
  return response.status === 204 ? null : response.json();
}
function element(tag, className, text) {
  const node = document.createElement(tag);
  node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}
function render() {
  grid.replaceChildren();
  for (const note of notes) {
    const card = element('article', `note${note.highlighted ? ' highlighted' : ''}`);
    const top = element('div', 'note-top');
    const date = new Date(note.created_at);
    const time = element('time', '', new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', year: 'numeric', hour: '2-digit', minute: '2-digit' }).format(date));
    time.dateTime = note.created_at;
    top.append(time);
    if (note.highlighted) card.setAttribute('aria-label', 'Earmarked note');
    const content = element('p', 'note-text', note.text);
    const bottom = element('div', 'note-bottom');
    const actions = element('div', 'note-options');
    const highlight = element('button', `note-action${note.highlighted ? ' active' : ''}`, note.highlighted ? 'Remove earmark' : 'Earmark');
    highlight.setAttribute('aria-pressed', String(note.highlighted));
    highlight.addEventListener('click', async () => {
      highlight.disabled = true;
      try {
        const updated = await api(`/api/notes/${note.id}`, { method: 'PATCH', body: JSON.stringify({ highlighted: !note.highlighted }) });
        notes = notes.map(item => item.id === note.id ? updated : item);
        render();
        document.querySelector(`[data-highlight="${note.id}"]`)?.focus();
        message(updated.highlighted ? 'Note earmarked.' : 'Earmark removed.');
      } catch (error) { message(error.message, true); highlight.disabled = false; }
    });
    highlight.dataset.highlight = note.id;
    const remove = element('button', 'note-action delete', 'Delete');
    remove.addEventListener('click', () => { pendingDelete = note.id; dialog.returnValue = ''; dialog.showModal(); });
    actions.append(highlight, remove);
    bottom.append(actions);
    card.append(top, content, bottom);
    grid.append(card);
  }
  document.querySelector('#count').textContent = total;
  document.querySelector('#empty').hidden = total !== 0;
  more.hidden = notes.length >= total;
}
async function load(append = false) {
  if (loading) return;
  loading = true;
  grid.setAttribute('aria-busy', 'true');
  more.disabled = true;
  try {
    const result = await api(`/api/notes?limit=100&offset=${append ? notes.length : 0}`);
    notes = append ? [...notes, ...result.notes.filter(item => !notes.some(old => old.id === item.id))] : result.notes;
    total = result.total;
    render();
  } catch (error) { message('Couldn’t load your notes. Refresh to try again.', true); }
  finally { loading = false; more.disabled = false; grid.setAttribute('aria-busy', 'false'); }
}
form.addEventListener('submit', async event => {
  event.preventDefault();
  if (!input.value.trim()) { message('Write a little something first.'); input.focus(); return; }
  save.disabled = true;
  const submitted = input.value;
  try {
    const created = await api('/api/notes', { method: 'POST', body: JSON.stringify({ text: submitted }) });
    notes.unshift(created);
    total += 1;
    if (input.value === submitted) input.value = '';
    render();
    message('Note saved. A little less to keep in your head.');
    input.focus();
  } catch (error) { message(error.message, true); }
  finally { save.disabled = false; }
});
input.addEventListener('keydown', event => {
  if ((event.ctrlKey || event.metaKey) && event.key === 'Enter' && !save.disabled) form.requestSubmit();
});
dialog.addEventListener('close', async () => {
  const id = pendingDelete;
  pendingDelete = null;
  if (dialog.returnValue !== 'delete' || id === null) return;
  try {
    await api(`/api/notes/${id}`, { method: 'DELETE' });
    notes = notes.filter(note => note.id !== id);
    total -= 1;
    render();
    message('Note deleted.');
    input.focus();
  } catch (error) { message(error.message, true); }
});
more.addEventListener('click', () => load(true));
load();
