// Chat functionality
let messageContainer;
let selectedFile = null;
let selectedFileBase64 = null;
let isUserScrolledUp = false;

function getBotAvatarHtml() {
    return `
        <div class="w-8 h-8 rounded-lg flex items-center justify-center mr-3 flex-shrink-0 overflow-hidden">
            <img src="agent-icon.svg" alt="AI Agent" class="w-8 h-8" />
        </div>`;
}

function getUserAvatarHtml() {
    const username = window.currentUsername || 'U';
    const initials = username.substring(0, 2).toUpperCase();
    return `
        <div class="w-8 h-8 rounded-full bg-indigo-500 flex items-center justify-center ml-3 flex-shrink-0">
            <span class="text-xs font-semibold text-white">${initials}</span>
        </div>`;
}

function formatTimestamp(date = new Date()) {
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function smartScroll() {
    if (!isUserScrolledUp) {
        messageContainer.scrollTop = messageContainer.scrollHeight;
    }
}

function initializeChat() {
    if (typeof marked === 'undefined') {
        return;
    }

    marked.setOptions({ gfm: true, tables: true, breaks: true });
    messageContainer = document.getElementById('messageContainer');
    messageContainer.addEventListener('scroll', handleScroll);
}

function handleScroll() {
    const scrollBtn = document.getElementById('scrollBottomBtn');
    const threshold = 100;
    const isAtBottom = messageContainer.scrollHeight - messageContainer.scrollTop - messageContainer.clientHeight < threshold;
    isUserScrolledUp = !isAtBottom;
    if (scrollBtn) scrollBtn.classList.toggle('visible', isUserScrolledUp);
}

function scrollToBottom() {
    messageContainer.scrollTop = messageContainer.scrollHeight;
    const scrollBtn = document.getElementById('scrollBottomBtn');
    if (scrollBtn) scrollBtn.classList.remove('visible');
}

function createStreamingMessage() {
    const messageDiv = document.createElement('div');
    messageDiv.className = 'flex mb-4';
    messageDiv.innerHTML = `
        ${getBotAvatarHtml()}
        <div class="message-bubble-ai rounded-lg p-3 max-w-4xl ai-response">
            <button class="copy-button" data-copy-text="" onclick="copyMessageContent(this)">📋 Copy</button>
            <div class="streaming-content"></div>
            <div class="message-timestamp">${formatTimestamp()}</div>
        </div>
    `;
    messageContainer.appendChild(messageDiv);
    smartScroll();
    return messageDiv;
}

function updateStreamingMessage(messageDiv, content, isFinal = false) {
    const contentDiv = messageDiv.querySelector('.streaming-content');
    const copyButton = messageDiv.querySelector('.copy-button');
    contentDiv.innerHTML = marked.parse(content);
    copyButton.setAttribute('data-copy-text', content);
    if (isFinal) {
        contentDiv.classList.add('streaming-complete');
    }
    smartScroll();
}

const retryCallbacks = new Map();
let retryIdCounter = 0;

function addMessage(content, sender, options = {}) {
    const messageDiv = document.createElement('div');
    messageDiv.className = 'flex mb-4';
    const timestamp = formatTimestamp();
    const { isError = false, retryCallback = null } = options;

    if (sender === 'user') {
        messageDiv.innerHTML = `
            <div class="ml-auto flex">
                <div class="message-bubble-user rounded-lg p-3 max-w-3xl">
                    <button class="copy-button" data-copy-text="${escapeHtml(content)}" onclick="copyMessageContent(this)">📋 Copy</button>
                    <p>${escapeHtml(content)}</p>
                    <div class="message-timestamp">${timestamp}</div>
                </div>
                ${getUserAvatarHtml()}
            </div>
        `;
    } else {
        let retryButton = '';
        if (isError && retryCallback) {
            const retryId = ++retryIdCounter;
            retryCallbacks.set(retryId, retryCallback);
            retryButton = `<button class="retry-button" onclick="executeRetry(${retryId})">🔄 Retry</button>`;
        }
        messageDiv.innerHTML = `
            ${getBotAvatarHtml()}
            <div class="message-bubble-ai rounded-lg p-3 max-w-4xl ai-response ${isError ? 'error-message' : ''}">
                <button class="copy-button" data-copy-text="${escapeHtml(content)}" onclick="copyMessageContent(this)">📋 Copy</button>
                ${marked.parse(content)}
                ${retryButton}
                <div class="message-timestamp">${timestamp}</div>
            </div>
        `;
    }

    messageContainer.appendChild(messageDiv);
    smartScroll();
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
    loadingDiv.className = 'flex mb-4';
    loadingDiv.innerHTML = `
        ${getBotAvatarHtml()}
        <div class="message-bubble-ai rounded-lg p-3">
            <div class="flex items-center gap-1">
                <span class="text-sm text-gray-500 dark:text-gray-400 mr-2">Thinking</span>
                <div class="w-2 h-2 bg-emerald-500 rounded-full typing-dot"></div>
                <div class="w-2 h-2 bg-emerald-500 rounded-full typing-dot"></div>
                <div class="w-2 h-2 bg-emerald-500 rounded-full typing-dot"></div>
            </div>
        </div>
    `;
    messageContainer.appendChild(loadingDiv);
    smartScroll();
    return loadingId;
}

function removeLoading(loadingId) {
    const loadingDiv = document.getElementById(loadingId);
    if (loadingDiv) loadingDiv.remove();
}

function escapeHtml(unsafe) {
    return unsafe
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
}

function copyMessageContent(button) {
    const text = button.getAttribute('data-copy-text');

    if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text).then(() => {
            showCopySuccess(button);
        }).catch(() => fallbackCopy(text, button));
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

function showCopySuccess(button) {
    const originalText = button.innerHTML;
    button.innerHTML = '✓ Copied';
    button.classList.add('copied');
    setTimeout(() => {
        button.innerHTML = originalText;
        button.classList.remove('copied');
    }, 2000);
}

async function sendMessage(message, config, auth) {
    const apiEndpoint = getApiEndpoint(config);

    const requestBody = { prompt: message };

    if (selectedFileBase64 && selectedFile) {
        requestBody.fileBase64 = selectedFileBase64;
        requestBody.fileName = selectedFile.name;
    }

    const headers = {
        'Content-Type': 'application/json',
        'Accept': 'text/plain, text/event-stream'
    };

    if (config.authType === 'cognito' || config.mode === 'aws') {
        // accessToken has 'client_id' claim required by AgentCore allowedClients
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

let pdfObjectUrl = null;

function handleFileSelect(file) {
    if (!file) return;

    // Revoke previous object URL to prevent memory leak
    if (pdfObjectUrl) {
        URL.revokeObjectURL(pdfObjectUrl);
        pdfObjectUrl = null;
    }

    selectedFile = file;
    const reader = new FileReader();
    reader.onload = function(e) {
        selectedFileBase64 = e.target.result.split(',')[1];

        document.getElementById('filePreview').classList.remove('hidden');
        document.getElementById('fileName').textContent = `📎 ${file.name}`;

        const previewImg = document.getElementById('filePreviewImg');
        const pdfPreview = document.getElementById('pdfPreview');

        if (file.type === 'application/pdf' || file.name.toLowerCase().endsWith('.pdf')) {
            previewImg.classList.add('hidden');
            pdfPreview.classList.remove('hidden');
            pdfObjectUrl = URL.createObjectURL(file);
            pdfPreview.onclick = () => window.open(pdfObjectUrl, '_blank');
        } else {
            pdfPreview.classList.add('hidden');
            previewImg.src = e.target.result;
            previewImg.classList.remove('hidden');
        }
    };
    reader.readAsDataURL(file);
}

function clearSelectedFile() {
    selectedFile = null;
    selectedFileBase64 = null;
    if (pdfObjectUrl) {
        URL.revokeObjectURL(pdfObjectUrl);
        pdfObjectUrl = null;
    }
    document.getElementById('fileInput').value = '';
    document.getElementById('filePreview').classList.add('hidden');
    document.getElementById('filePreviewImg').src = '';
    document.getElementById('filePreviewImg').classList.add('hidden');
    document.getElementById('pdfPreview').classList.add('hidden');
}

async function processStreamingResponse(response, loadingId = null) {
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let fullResponse = '';
    let messageDiv = null;
    let buffer = '';
    let loadingRemoved = false;
    let lastUpdateTime = Date.now();
    let pauseIndicator = null;
    let isSSE = null;
    let eventDataLines = [];  // Track data lines within current event

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
            if (pauseIndicator) {
                pauseIndicator.remove();
                pauseIndicator = null;
            }

            const chunk = decoder.decode(value, { stream: true });

            if (isSSE === null) {
                isSSE = chunk.trimStart().startsWith('data:');
            }

            if (isSSE) {
                buffer += chunk;
                const lines = buffer.split('\n');
                buffer = lines.pop() || '';

                for (const line of lines) {
                    if (line.startsWith('data:')) {
                        eventDataLines.push(line.substring(5));
                    } else if (line === '' || line === '\r') {
                        // Blank line = end of event, join data lines with \n per SSE spec
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

            if (!messageDiv && fullResponse.length > 0) {
                messageDiv = createStreamingMessage();
            }

            if (messageDiv) {
                updateStreamingMessage(messageDiv, fullResponse, false);
            }
        }

        // Flush remaining SSE data
        if (eventDataLines.length > 0) {
            fullResponse += eventDataLines.join('\n');
        }
    } finally {
        clearInterval(pauseCheckInterval);
        if (pauseIndicator) pauseIndicator.remove();
        if (!loadingRemoved && loadingId) removeLoading(loadingId);
    }

    if (messageDiv) {
        updateStreamingMessage(messageDiv, fullResponse, true);
    }

    return fullResponse;
}

function openImageModal(src) {
    const modal = document.getElementById('imageModal');
    const modalImg = document.getElementById('modalImage');
    modalImg.src = src;
    modal.classList.remove('hidden');
}

function closeImageModal() {
    document.getElementById('imageModal').classList.add('hidden');
}

document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') closeImageModal();
});
