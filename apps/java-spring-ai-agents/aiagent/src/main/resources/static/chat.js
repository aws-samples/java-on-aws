// Chat functionality
const chatState = {
    messageContainer: null,
    chatScreen: null,
    selectedFile: null,
    selectedFileBase64: null,
    isUserScrolledUp: false,
    isStreaming: false,
    followStream: false,
    scrollNavTimeout: null,
    lastParseTime: 0,
    pdfObjectUrl: null
};
const PARSE_THROTTLE_MS = 50;

function getInputAreaHeight() {
    const el = document.querySelector('.input-area');
    return el ? el.offsetHeight : 0;
}

function getHeaderHeight() {
    const el = document.querySelector('.chat-header');
    return el ? el.offsetHeight : 0;
}

function getBotAvatarHtml() {
    return '';
}

function getUserAvatarHtml() {
    return '';
}

function formatTimestamp(date = new Date()) {
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function smartScroll() {
    if (chatState.followStream) {
        const lastMsg = chatState.messageContainer.lastElementChild;
        if (lastMsg) {
            const screenRect = chatState.chatScreen.getBoundingClientRect();
            const msgRect = lastMsg.getBoundingClientRect();
            const inputH = getInputAreaHeight();
            if (msgRect.bottom > screenRect.bottom - inputH - 16) {
                chatState.chatScreen.scrollTop = lastMsg.offsetTop + lastMsg.offsetHeight - chatState.chatScreen.clientHeight + inputH + 16;
            }
        }
    }
    updateScrollBottomBtn();
    clearTimeout(chatState.scrollNavTimeout);
    chatState.scrollNavTimeout = setTimeout(updateScrollNavButtons, 100);
}

function updateScrollBottomBtn() {
    const scrollBtn = document.getElementById('scrollBottomBtn');
    if (!scrollBtn) return;
    const lastMsg = chatState.messageContainer.lastElementChild;
    if (!lastMsg || lastMsg.querySelector('.typing-dot')) {
        scrollBtn.classList.remove('visible', 'streaming');
        return;
    }
    if (chatState.followStream) {
        scrollBtn.classList.remove('visible', 'streaming');
        return;
    }
    const screenRect = chatState.chatScreen.getBoundingClientRect();
    const msgRect = lastMsg.getBoundingClientRect();
    const isAligned = msgRect.bottom <= screenRect.bottom - getInputAreaHeight() + 20;
    scrollBtn.classList.toggle('visible', !isAligned);
    scrollBtn.classList.toggle('streaming', !isAligned && chatState.isStreaming);
}

function initializeChat() {
    if (typeof marked === 'undefined') return;
    marked.setOptions({ gfm: true, tables: true, breaks: true });
    chatState.messageContainer = document.getElementById('messageContainer');
    chatState.chatScreen = document.getElementById('chatScreen');
    chatState.chatScreen.addEventListener('scroll', handleScroll);
    const interrupt = () => { if (chatState.isStreaming) chatState.followStream = false; updateScrollBottomBtn(); };
    chatState.chatScreen.addEventListener('wheel', interrupt, { passive: true });
    chatState.chatScreen.addEventListener('touchmove', interrupt, { passive: true });
    document.addEventListener('keydown', (e) => { if (['ArrowUp','ArrowDown','PageUp','PageDown'].includes(e.key)) interrupt(); });
}

function handleScroll() {
    updateScrollBottomBtn();
    clearTimeout(chatState.scrollNavTimeout);
    chatState.scrollNavTimeout = setTimeout(updateScrollNavButtons, 100);
}

function updateScrollNavButtons() {
    const screenRect = chatState.chatScreen.getBoundingClientRect();
    chatState.messageContainer.querySelectorAll('.msg-ai').forEach(msg => {
        const rect = msg.getBoundingClientRect();
        const topHidden = rect.top < screenRect.top;
        const bottomHidden = rect.bottom > screenRect.bottom && rect.top < screenRect.bottom;
        const top = msg.querySelector('.scroll-top-button');
        const end = msg.querySelector('.scroll-end-button');
        if (top) top.classList.toggle('nav-visible', topHidden);
        if (end) end.classList.toggle('nav-visible', bottomHidden);
    });
}

function scrollToBottom() {
    const lastMsg = chatState.messageContainer.lastElementChild;
    if (lastMsg) {
        chatState.chatScreen.scrollTo({ top: lastMsg.offsetTop + lastMsg.offsetHeight - chatState.chatScreen.clientHeight + getInputAreaHeight() + 16, behavior: 'smooth' });
    }
    chatState.followStream = true;
    updateScrollBottomBtn();
}

function createStreamingMessage() {
    chatState.isStreaming = true;
    chatState.followStream = true;
    const messageDiv = document.createElement('div');
    messageDiv.className = 'msg msg-ai';
    messageDiv.innerHTML = `
        ${getBotAvatarHtml()}
        <div class="msg-bubble msg-bubble-ai ai-response">
            <button class="copy-button" data-copy-text="" onclick="copyMessageContent(this)" title="Copy">${COPY_ICON}</button>
            <button class="scroll-end-button" onclick="scrollMsgToEnd(this)" title="Scroll to end">${ARROW_DOWN_ICON}</button>
            <button class="scroll-top-button" onclick="scrollMsgToTop(this)" title="Scroll to top">${ARROW_UP_ICON}</button>
            <div class="streaming-content"></div>
        </div>
    `;
    chatState.messageContainer.appendChild(messageDiv);
    smartScroll();
    return messageDiv;
}

function fixTableSeparators(md) {
    return md.replace(/((?:\|[^\n]+\|)\n)(\|(?:\s*-+\s*\|)+)\n/g, function(match, headerLine, sepLine) {
        var headerCols = (headerLine.match(/\|/g) || []).length - 1;
        var sepCols = (sepLine.match(/---/g) || []).length;
        if (sepCols < headerCols) {
            return headerLine + sepLine + '---|'.repeat(headerCols - sepCols) + '\n';
        }
        return match;
    });
}

function updateStreamingMessage(messageDiv, content, isFinal = false) {
    const contentDiv = messageDiv.querySelector('.streaming-content');
    const copyButton = messageDiv.querySelector('.copy-button');
    
    const now = Date.now();
    if (isFinal || now - chatState.lastParseTime >= PARSE_THROTTLE_MS) {
        contentDiv.innerHTML = marked.parse(fixTableSeparators(content));
        chatState.lastParseTime = now;
    }
    copyButton.dataset.copyText = content;
    
    if (isFinal) {
        chatState.isStreaming = false;
        contentDiv.classList.add('streaming-complete');
        contentDiv.querySelectorAll('img').forEach(img => {
            img.onclick = () => openImageModal(img.src);
            if (!img.complete) img.onload = smartScroll;
        });
    }
    smartScroll();
}

const retryCallbacks = new Map();
let retryIdCounter = 0;
const MAX_RETRY_CALLBACKS = 10;

function addMessage(content, sender, options = {}) {
    const messageDiv = document.createElement('div');
    const { isError = false, retryCallback = null } = options;

    if (sender === 'user') {
        messageDiv.className = 'msg msg-user';
        messageDiv.innerHTML = `
            <div class="msg-bubble msg-bubble-user">
                <button class="copy-button" data-copy-text="${escapeHtml(content)}" onclick="copyMessageContent(this)" title="Copy">${COPY_ICON}</button>
                <p>${escapeHtml(content)}</p>
            </div>
        `;
    } else {
        let errorActions = '';
        if (isError && retryCallback) {
            const retryId = ++retryIdCounter;
            if (retryCallbacks.size >= MAX_RETRY_CALLBACKS) {
                retryCallbacks.delete(retryCallbacks.keys().next().value);
            }
            retryCallbacks.set(retryId, retryCallback);
            errorActions = `<div class="error-actions">
                <button class="retry-button" onclick="executeRetry(${retryId})">↻ Retry</button>
                <button class="copy-button" data-copy-text="${escapeHtml(content)}" onclick="copyMessageContent(this)" title="Copy">${COPY_ICON}</button>
            </div>`;
        }
        messageDiv.className = 'msg msg-ai';
        const copyBtn = isError ? '' : `<button class="copy-button" data-copy-text="${escapeHtml(content)}" onclick="copyMessageContent(this)" title="Copy">${COPY_ICON}</button>`;
        messageDiv.innerHTML = `
            ${getBotAvatarHtml()}
            <div class="msg-bubble msg-bubble-ai ai-response ${isError ? 'error-message' : ''}">
                ${copyBtn}
                <button class="scroll-end-button" onclick="scrollMsgToEnd(this)" title="Scroll to end">${ARROW_DOWN_ICON}</button>
                <button class="scroll-top-button" onclick="scrollMsgToTop(this)" title="Scroll to top">${ARROW_UP_ICON}</button>
                ${marked.parse(fixTableSeparators(content))}
                ${errorActions}
            </div>
        `;
    }

    chatState.messageContainer.appendChild(messageDiv);
    messageDiv.querySelectorAll('.ai-response img').forEach(img => img.onclick = () => openImageModal(img.src));
    if (sender !== 'user') smartScroll();
    return messageDiv;
}

function executeRetry(retryId) {
    const callback = retryCallbacks.get(retryId);
    if (callback) {
        retryCallbacks.delete(retryId);
        callback();
    }
}

function showLoading() {
    const loadingId = 'loading-' + Date.now();
    const loadingDiv = document.createElement('div');
    loadingDiv.id = loadingId;
    loadingDiv.className = 'msg msg-ai';
    loadingDiv.setAttribute('role', 'status');
    loadingDiv.setAttribute('aria-live', 'polite');
    loadingDiv.innerHTML = `
        <div style="display:flex;align-items:center;gap:3px;padding:10px 0;margin-left:14px;">
            <span class="sr-only">Loading response</span>
            <div class="typing-dot"></div>
            <div class="typing-dot"></div>
            <div class="typing-dot"></div>
        </div>
    `;
    chatState.messageContainer.appendChild(loadingDiv);
    return loadingId;
}

function removeLoading(loadingId) {
    const el = document.getElementById(loadingId);
    if (el) el.remove();
}

function escapeHtml(unsafe) {
    return unsafe
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
}

function scrollMsgToTop(button) {
    const msg = button.closest('.msg');
    chatState.chatScreen.scrollTo({ top: msg.offsetTop - getHeaderHeight(), behavior: 'smooth' });
}

function scrollMsgToEnd(button) {
    const msg = button.closest('.msg');
    chatState.chatScreen.scrollTo({ top: msg.offsetTop + msg.offsetHeight - chatState.chatScreen.clientHeight + getInputAreaHeight() + 16, behavior: 'smooth' });
}

function copyMessageContent(button) {
    const text = button.dataset.copyText || '';
    if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text).then(() => showCopySuccess(button)).catch(() => fallbackCopy(text, button));
    } else {
        fallbackCopy(text, button);
    }
}

function fallbackCopy(text, button) {
    const textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.style.position = 'fixed';
    textarea.style.opacity = '0';
    document.body.appendChild(textarea);
    textarea.select();
    document.execCommand('copy');
    document.body.removeChild(textarea);
    showCopySuccess(button);
}

const COPY_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/></svg>';
const CHECK_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="20 6 9 17 4 12"/></svg>';
const ARROW_UP_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="18 15 12 9 6 15"/></svg>';
const ARROW_DOWN_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="6 9 12 15 18 9"/></svg>';

function showCopySuccess(button) {
    button.innerHTML = CHECK_ICON;
    button.classList.add('copied');
    setTimeout(() => {
        button.innerHTML = COPY_ICON;
        button.classList.remove('copied');
    }, 2000);
}

async function sendMessage(message, config, auth) {
    const apiEndpoint = getApiEndpoint(config);
    const requestBody = { prompt: message };

    if (chatState.selectedFileBase64 && chatState.selectedFile) {
        requestBody.fileBase64 = chatState.selectedFileBase64;
        requestBody.fileName = chatState.selectedFile.name;
    }

    const models = getModels(config);
    if (models.length > 0) {
        const selectedModel = getSelectedModel();
        if (selectedModel) {
            requestBody.modelId = selectedModel;
        }
    }

    const headers = {
        'Content-Type': 'application/json',
        'Accept': 'text/plain, text/event-stream',
        'X-Amzn-Bedrock-AgentCore-Runtime-Session-Id': getSessionId()
    };

    if (config.authType === 'cognito' || config.mode === 'aws') {
        headers['Authorization'] = `Bearer ${auth.accessToken}`;
    } else {
        headers['Authorization'] = auth.username;
    }

    const response = await fetch(apiEndpoint, {
        method: 'POST',
        headers: headers,
        body: JSON.stringify(requestBody)
    });

    if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`API request failed: ${response.status} ${errorText}`);
    }

    return response;
}

function handleFileSelect(file) {
    if (!file) return;
    if (chatState.pdfObjectUrl) { URL.revokeObjectURL(chatState.pdfObjectUrl); chatState.pdfObjectUrl = null; }

    chatState.selectedFile = file;
    const reader = new FileReader();
    reader.onload = function(e) {
        chatState.selectedFileBase64 = e.target.result.split(',')[1];
        document.getElementById('filePreview').classList.remove('hidden');
        document.getElementById('fileName').textContent = `📎 ${file.name}`;

        const previewImg = document.getElementById('filePreviewImg');
        const pdfPreview = document.getElementById('pdfPreview');

        if (file.type === 'application/pdf' || file.name.toLowerCase().endsWith('.pdf')) {
            previewImg.classList.add('hidden');
            pdfPreview.classList.remove('hidden');
            chatState.pdfObjectUrl = URL.createObjectURL(file);
            pdfPreview.onclick = () => window.open(chatState.pdfObjectUrl, '_blank');
        } else {
            pdfPreview.classList.add('hidden');
            previewImg.src = e.target.result;
            previewImg.classList.remove('hidden');
        }
    };
    reader.readAsDataURL(file);
}

function clearSelectedFile() {
    chatState.selectedFile = null;
    chatState.selectedFileBase64 = null;
    if (chatState.pdfObjectUrl) { URL.revokeObjectURL(chatState.pdfObjectUrl); chatState.pdfObjectUrl = null; }
    document.getElementById('fileInput').value = '';
    document.getElementById('filePreview').classList.add('hidden');
    document.getElementById('filePreviewImg').src = '';
    document.getElementById('filePreviewImg').classList.add('hidden');
    document.getElementById('pdfPreview').classList.add('hidden');
}

async function processStreamingResponse(response, loadingId = null) {
    if (!response.body) {
        if (loadingId) removeLoading(loadingId);
        throw new Error('Response body is not available');
    }
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let fullResponse = '';
    let messageDiv = null;
    let buffer = '';
    let loadingRemoved = false;
    let lastUpdateTime = Date.now();
    let pauseIndicator = null;
    let isSSE = null;
    let eventDataLines = [];

    const pauseCheckInterval = setInterval(() => {
        const timeSinceUpdate = Date.now() - lastUpdateTime;
        if (timeSinceUpdate > 2000 && messageDiv && !pauseIndicator) {
            pauseIndicator = document.createElement('span');
            pauseIndicator.className = 'streaming-pause-indicator';
            pauseIndicator.innerHTML = ' <span class="typing-dot-inline">●</span><span class="typing-dot-inline">●</span><span class="typing-dot-inline">●</span>';
            const contentDiv = messageDiv.querySelector('.streaming-content');
            if (contentDiv) contentDiv.appendChild(pauseIndicator);
        }
    }, 500);

    try {
        while (true) {
            const { done, value } = await reader.read();
            if (done) break;

            lastUpdateTime = Date.now();
            if (pauseIndicator) { pauseIndicator.remove(); pauseIndicator = null; }

            const chunk = decoder.decode(value, { stream: true });
            if (isSSE === null) isSSE = chunk.trimStart().startsWith('data:');

            if (isSSE) {
                buffer += chunk;
                const lines = buffer.split('\n');
                buffer = lines.pop() || '';
                for (const line of lines) {
                    if (line.startsWith('data:')) {
                        eventDataLines.push(line.substring(5));
                    } else if (line === '' || line === '\r') {
                        if (eventDataLines.length > 0) {
                            fullResponse += eventDataLines.join('\n');
                            eventDataLines = [];
                        }
                    }
                }
            } else {
                fullResponse += chunk.replace(/\r/g, '');
            }

            if (!loadingRemoved && fullResponse.trim().length > 0 && loadingId) {
                removeLoading(loadingId);
                loadingRemoved = true;
            }
            if (!messageDiv && fullResponse.length > 0) messageDiv = createStreamingMessage();
            if (messageDiv) updateStreamingMessage(messageDiv, fullResponse, false);
        }

        if (eventDataLines.length > 0) fullResponse += eventDataLines.join('\n');
    } finally {
        clearInterval(pauseCheckInterval);
        if (pauseIndicator) pauseIndicator.remove();
        if (!loadingRemoved && loadingId) removeLoading(loadingId);
    }

    if (messageDiv) updateStreamingMessage(messageDiv, fullResponse, true);
    return fullResponse;
}

function openImageModal(src) {
    const modal = document.getElementById('imageModal');
    document.getElementById('modalImage').src = src;
    modal.classList.remove('hidden');
    const closeBtn = modal.querySelector('.modal-close');
    closeBtn.focus();
    modal.addEventListener('keydown', trapFocus);
}

function trapFocus(e) {
    if (e.key === 'Tab') {
        e.preventDefault();
        document.querySelector('#imageModal .modal-close').focus();
    }
}

function closeImageModal() {
    const modal = document.getElementById('imageModal');
    modal.classList.add('hidden');
    modal.removeEventListener('keydown', trapFocus);
}

document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') closeImageModal();
});
