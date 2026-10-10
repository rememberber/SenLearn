(() => {
  'use strict';
  const THEMES = Object.freeze(['forest', 'native', 'play', 'night']);
  const THEME_NAMES = Object.freeze({forest: '森间书桌', native: '清透原生', play: '探索乐园', night: '月光共读'});
  const STORAGE = Object.freeze({theme: 'senlearn.theme.v1', motion: 'senlearn.reduceMotion.v1', speed: 'senlearn.speed.v1'});
  const PAGES = Object.freeze([
    {caption: 'A little forest friend', sentences: ['The little squirrel lives in the forest.', 'It finds a seed under a tree.'], selected: [0, 2]},
    {caption: 'A tiny seed, a new beginning', sentences: ['The squirrel plants the tiny seed.', 'A new tree will grow in the forest.'], selected: [0, 1]}
  ]);
  const DICTIONARY = Object.freeze({the: '这 / 那', little: '小小的', squirrel: '松鼠', lives: '住在', in: '在……里', forest: '森林', it: '它', finds: '找到', a: '一 / 一个', seed: '种子', under: '在……下面', tree: '树', plants: '种下', tiny: '小小的', new: '新的', will: '将会', grow: '生长'});
  const $ = (id) => document.getElementById(id);
  const root = document.documentElement;
  const dialog = $('settings-dialog');
  const synth = window.speechSynthesis;
  let storageAvailable = true;
  let speechVersion = 0;
  let currentUtterance = null;
  let localVoice = null;
  let lastAudio = null;
  const state = {page: 0, sentence: 0, word: 2, theme: 'forest', speed: 1, reduceMotion: false, playing: false};

  function readSetting(key) {
    try { return window.localStorage.getItem(key); }
    catch { storageAvailable = false; return null; }
  }
  function saveSetting(key, value) {
    try { window.localStorage.setItem(key, String(value)); return true; }
    catch { storageAvailable = false; updateStorageMessage(); return false; }
  }
  function updateStorageMessage(message) {
    const element = $('storage-message');
    element.textContent = storageAvailable ? (message || '主题更改会自动保存在这台设备，下次打开继续使用。') : '这次的设置已经生效；浏览器暂时无法保存，关闭页面后可能需要重新选择。';
    element.classList.toggle('is-warning', !storageAvailable);
  }
  function applyTheme(value, persist = true) {
    const theme = THEMES.includes(value) ? value : 'forest';
    state.theme = theme;
    root.setAttribute('data-theme', theme);
    document.querySelectorAll('input[name="theme"]').forEach((input) => { input.checked = input.value === theme; });
    if (persist) {
      saveSetting(STORAGE.theme, theme);
      updateStorageMessage(`已切换为「${THEME_NAMES[theme]}」，并保存在这台设备。`);
    }
  }
  function announce(message) { $('audio-status').textContent = message; }
  function cleanWord(word) { return word.replace(/[.,!?]/g, ''); }
  function selectedWord() { return cleanWord(PAGES[state.page].sentences[state.sentence].split(' ')[state.word]); }

  function renderSentences() {
    const wrapper = $('sentences');
    wrapper.replaceChildren();
    PAGES[state.page].sentences.forEach((text, sentenceIndex) => {
      const row = document.createElement('div');
      row.className = 'sentence';
      row.id = `sentence-${sentenceIndex}`;
      row.setAttribute('role', 'group');
      row.setAttribute('aria-label', `第 ${sentenceIndex + 1} 句：${text}`);
      const number = document.createElement('button');
      number.className = 'sentence-number';
      number.type = 'button';
      number.textContent = String(sentenceIndex + 1).padStart(2, '0');
      number.setAttribute('aria-label', `选择第 ${sentenceIndex + 1} 句`);
      number.addEventListener('click', () => {
        stopAudio(false);
        state.sentence = sentenceIndex;
        state.word = 0;
        lastAudio = null;
        updateSelection();
        announce(`已选择第 ${sentenceIndex + 1} 句，可以听整句。`);
      });
      const words = document.createElement('div');
      words.className = 'sentence-words';
      words.lang = 'en';
      text.split(' ').forEach((word, wordIndex) => {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'word';
        button.id = `word-${sentenceIndex}-${wordIndex}`;
        button.textContent = word;
        button.setAttribute('aria-label', `点读 ${cleanWord(word)}`);
        button.addEventListener('click', () => {
          state.sentence = sentenceIndex;
          state.word = wordIndex;
          lastAudio = null;
          updateSelection();
          playSelection('word');
        });
        words.append(button);
      });
      row.append(number, words);
      wrapper.append(row);
    });
    updateSelection();
  }
  function updateSelection() {
    const word = selectedWord();
    document.querySelectorAll('.sentence').forEach((element, index) => {
      element.classList.toggle('is-current', index === state.sentence);
      element.querySelector('.sentence-number').setAttribute('aria-pressed', String(index === state.sentence));
      element.querySelectorAll('.word').forEach((button, wordIndex) => {
        const selected = index === state.sentence && wordIndex === state.word;
        button.classList.toggle('selected', selected);
        button.setAttribute('aria-pressed', String(selected));
      });
    });
    $('selected-word').textContent = word;
    $('word-translation').textContent = DICTIONARY[word.toLowerCase()] || '';
    $('selection-caption').textContent = `已选中 ${word}`;
    $('listen-word-caption').textContent = word;
    $('listen-sentence-caption').textContent = `第 ${state.sentence + 1} 句`;
    $('word-speak').setAttribute('aria-label', `播放 ${word} 的发音`);
    $('listen-word').setAttribute('aria-label', `听单词 ${word}`);
    $('listen-sentence').setAttribute('aria-label', `听第 ${state.sentence + 1} 句`);
    $('repeat-caption').textContent = lastAudio?.type === 'sentence' ? '再听刚才的句子' : '再听当前单词';
  }
  function renderPage() {
    $('header-page').textContent = `${String(state.page + 1).padStart(2, '0')} / 02`;
    $('page-label').replaceChildren();
    $('page-label').append('第 ');
    const pageNumber = document.createElement('strong'); pageNumber.textContent = state.page + 1;
    const total = document.createElement('span'); total.textContent = '/ 2';
    $('page-label').append(pageNumber, ' 页 ', total);
    $('printed-page').textContent = String(state.page + 1).padStart(2, '0');
    $('lesson-caption').textContent = PAGES[state.page].caption;
    $('previous-page').disabled = state.page === 0;
    $('next-page').disabled = state.page === PAGES.length - 1;
    renderSentences();
  }
  function changePage(direction) {
    const next = state.page + direction;
    if (next < 0 || next >= PAGES.length) return;
    stopAudio(false);
    state.page = next;
    [state.sentence, state.word] = PAGES[next].selected;
    lastAudio = null;
    renderPage();
    announce(`已翻到第 ${next + 1} 页，选中 ${selectedWord()}。`);
    const focusTarget = direction > 0 && next === PAGES.length - 1 ? $('previous-page') : direction < 0 && next === 0 ? $('next-page') : null;
    if (focusTarget) focusTarget.focus({preventScroll: true});
  }
  function setPlaying(playing, type) {
    state.playing = playing;
    $('stop-audio').disabled = !playing;
    $('audio-indicator').classList.toggle('is-playing', playing);
    document.querySelectorAll('.sentence').forEach((row, index) => row.classList.toggle('is-speaking', playing && type === 'sentence' && index === state.sentence));
  }
  function stopAudio(withAnnouncement = true) {
    speechVersion += 1;
    if (synth) synth.cancel();
    currentUtterance = null;
    const wasPlaying = state.playing;
    setPlaying(false);
    if (withAnnouncement && wasPlaying) announce('已停止播放，可以继续点读。');
  }
  function updateVoices() {
    const available = synth?.getVoices() || [];
    const english = available.filter((voice) => voice.localService === true && /^en(?:-|_|$)/i.test(voice.lang));
    localVoice = english.find((voice) => /^en-US$/i.test(voice.lang)) || english[0] || null;
    $('voice-note').textContent = localVoice ? '设备本地英文声音 · 试听不发送文字到网络' : '此设备未提供本地英文声音 · 本原型暂不能离线试听';
  }
  function playSelection(type, previous = null) {
    stopAudio(false);
    updateVoices();
    const item = previous || {type, text: type === 'sentence' ? PAGES[state.page].sentences[state.sentence] : selectedWord()};
    if (!synth || !localVoice || typeof window.SpeechSynthesisUtterance !== 'function') {
      announce(`已选中${type === 'sentence' ? `第 ${state.sentence + 1} 句` : ` ${selectedWord()}`}；设备没有可用的本地英文声音，暂不能试听。`);
      return;
    }
    const version = speechVersion;
    const utterance = new SpeechSynthesisUtterance(item.text);
    currentUtterance = utterance;
    utterance.voice = localVoice;
    utterance.lang = localVoice.lang;
    utterance.rate = state.speed;
    utterance.pitch = 1;
    utterance.volume = 1;
    lastAudio = {...item};
    updateSelection();
    setPlaying(true, item.type);
    announce(item.type === 'sentence' ? `准备朗读第 ${state.sentence + 1} 句…` : `准备朗读 ${item.text}…`);
    utterance.onstart = () => {
      if (version !== speechVersion) return;
      announce(item.type === 'sentence' ? `正在朗读第 ${state.sentence + 1} 句` : `正在朗读 ${item.text}`);
    };
    utterance.onend = () => {
      if (version !== speechVersion) return;
      currentUtterance = null;
      setPlaying(false);
      announce(item.type === 'sentence' ? '这句读完了，你也可以轻轻读一遍。' : `${item.text} 读完了，再试试下一个词吧。`);
    };
    utterance.onerror = (event) => {
      if (version !== speechVersion) return;
      currentUtterance = null;
      setPlaying(false);
      announce(event.error === 'canceled' || event.error === 'interrupted' ? '已停止播放。' : '设备本地声音暂时无法播放，请稍后再试。');
    };
    try { synth.speak(utterance); }
    catch { currentUtterance = null; setPlaying(false); announce('设备本地声音暂时无法播放，请稍后再试。'); }
  }

  const storedTheme = readSetting(STORAGE.theme);
  const storedMotion = readSetting(STORAGE.motion);
  const storedSpeed = readSetting(STORAGE.speed);
  applyTheme(storedTheme, false);
  state.reduceMotion = storedMotion === 'true';
  root.setAttribute('data-reduce-motion', String(state.reduceMotion));
  $('reduce-motion').checked = state.reduceMotion;
  state.speed = storedSpeed === '0.8' ? 0.8 : 1;
  $('reading-speed').value = String(state.speed);
  updateStorageMessage();
  renderPage();
  updateVoices();
  synth?.addEventListener('voiceschanged', updateVoices);

  document.querySelectorAll('input[name="theme"]').forEach((input) => input.addEventListener('change', () => { if (input.checked) applyTheme(input.value); }));
  $('reset-theme').addEventListener('click', () => applyTheme('forest'));
  $('reduce-motion').addEventListener('change', (event) => {
    state.reduceMotion = event.target.checked;
    root.setAttribute('data-reduce-motion', String(state.reduceMotion));
    saveSetting(STORAGE.motion, state.reduceMotion);
    updateStorageMessage('减少动态效果的偏好已保存在这台设备。');
  });
  $('reading-speed').addEventListener('change', (event) => {
    stopAudio(false);
    state.speed = event.target.value === '0.8' ? 0.8 : 1;
    saveSetting(STORAGE.speed, state.speed);
    announce(state.speed === 0.8 ? '语速已改为慢一点，下次播放生效。' : '语速已改为正常，下次播放生效。');
  });
  $('previous-page').addEventListener('click', () => changePage(-1));
  $('next-page').addEventListener('click', () => changePage(1));
  $('listen-word').addEventListener('click', () => playSelection('word'));
  $('word-speak').addEventListener('click', () => playSelection('word'));
  $('listen-sentence').addEventListener('click', () => playSelection('sentence'));
  $('repeat-audio').addEventListener('click', () => playSelection(lastAudio?.type || 'word', lastAudio));
  $('stop-audio').addEventListener('click', () => stopAudio());

  function openSettings() { if (!dialog.open) dialog.showModal(); }
  function closeSettings() { dialog.close(); }
  $('open-settings').addEventListener('click', openSettings);
  $('close-settings').addEventListener('click', closeSettings);
  $('done-settings').addEventListener('click', closeSettings);
  dialog.addEventListener('close', () => { $('open-settings').focus({preventScroll: true}); });
  dialog.addEventListener('click', (event) => {
    if (event.target !== dialog) return;
    const box = dialog.getBoundingClientRect();
    if (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom) closeSettings();
  });
  const motionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
  function updateMotionNote() { $('system-motion-note').textContent = motionQuery.matches ? '设备已开启减少动态效果，当前界面会保持静止。' : '同时尊重设备的减少动态效果设置。'; }
  updateMotionNote();
  motionQuery.addEventListener('change', updateMotionNote);
  window.addEventListener('pagehide', () => stopAudio(false));
  document.addEventListener('visibilitychange', () => { if (document.hidden) stopAudio(false); });
  if (new URLSearchParams(window.location.search).get('settings') === 'open') openSettings();
})();
