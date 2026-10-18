// Main application logic
document.addEventListener('DOMContentLoaded', async function() {
    initializeChat();

    const loginScreen = document.getElementById('loginScreen');
    const chatScreen = document.getElementById('chatScreen');
    const loginForm = document.getElementById('loginForm');
    const chatForm = document.getElementById('chatForm');
    const userInput = document.getElementById('userInput');
    const themeToggle = document.getElementById('themeToggle');
    const logoutBtn = document.getElementById('logoutBtn');
    const loginError = document.getElementById('loginError');
    const userDisplay = document.getElementById('userDisplay');
    const uploadBtn = document.getElementById('uploadBtn');
    const fileInput = document.getElementById('fileInput');
    const clearFileBtn = document.getElementById('clearFileBtn');

    const config = await loadConfig();

    // Auto-resize textarea
    userInput.addEventListener('input', function() {
        this.style.height = 'auto';
        this.style.height = this.scrollHeight + 'px';
    });

    // Submit on Enter, newline on Shift+Enter
    userInput.addEventListener('keydown', function(e) {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            chatForm.requestSubmit();
        }
    });

    if (uploadBtn) {
        if (isAttachmentsEnabled(config)) {
            uploadBtn.classList.remove('hidden');
        } else {
            uploadBtn.classList.add('hidden');
        }
    }

    // Initialize model selector
    const modelSelect = document.getElementById('modelSelect');
    const models = getModels(config);
    if (modelSelect && models.length > 0) {
        modelSelect.classList.remove('hidden');
        models.forEach(m => {
            const opt = document.createElement('option');
            opt.value = m.id;
            opt.textContent = m.name;
            if (m.default) opt.selected = true;
            modelSelect.appendChild(opt);
        });
        const saved = getSelectedModel();
        if (saved && models.some(m => m.id === saved)) {
            modelSelect.value = saved;
        } else {
            const def = models.find(m => m.default) || models[0];
            setSelectedModel(def.id);
        }
        modelSelect.addEventListener('change', () => setSelectedModel(modelSelect.value));
    } else if (modelSelect) {
        modelSelect.classList.add('hidden');
    }

    const loginMessage = document.getElementById('loginMessage');
    if (loginMessage) {
        if (config.authType === 'simple') {
            loginMessage.textContent = 'Local Mode — Enter any username to continue';
        } else {
            loginMessage.textContent = 'Sign in with your Cognito credentials';
        }
    }

    if (isAuthenticated()) {
        showChatScreen();
    } else {
        showLoginScreen();
    }

    loginForm.addEventListener('submit', async function(e) {
        e.preventDefault();
        const username = document.getElementById('username').value;
        const password = document.getElementById('password').value;
        loginError.classList.add('hidden');

        try {
            await authenticateUser(username, password, config);
            showChatScreen();
        } catch (error) {
            loginError.textContent = error.message || 'Authentication failed. Please check your credentials.';
            loginError.classList.remove('hidden');
        }
    });

    chatForm.addEventListener('submit', async function(e) {
        e.preventDefault();
        const message = userInput.value.trim();
        if (!message) return;

        if (message.length > 10000) {
            addMessage('Message too long. Please limit to 10,000 characters.', 'ai', { isError: true });
            return;
        }

        const userMsg = addMessage(message, 'user');
        requestAnimationFrame(() => {
            const headerH = document.querySelector('.chat-header').offsetHeight;
            const msgTop = userMsg.getBoundingClientRect().top + chatScreen.scrollTop - chatScreen.getBoundingClientRect().top;
            chatScreen.scrollTo({ top: msgTop - headerH - 24, behavior: 'smooth' });
        });
        userInput.value = '';
        userInput.style.height = 'auto';

        const auth = loadAuth();
        if (isSessionExpired(auth)) {
            addMessage('Your session has expired. Please log in again.', 'ai', { isError: true });
            setTimeout(() => { clearAuth(); showLoginScreen(); }, 2000);
            return;
        }

        const loadingId = showLoading();
        const lastMessage = message;

        try {
            const response = await sendMessage(message, config, auth);
            await processStreamingResponse(response, loadingId);
        } catch (error) {
            removeLoading(loadingId);
            const retryFn = async () => {
                const container = document.getElementById('messageContainer');
                const errorMsg = container.lastElementChild;
                if (errorMsg) errorMsg.remove();

                const freshAuth = loadAuth();
                if (isSessionExpired(freshAuth)) {
                    addMessage('Your session has expired. Please log in again.', 'ai', { isError: true });
                    setTimeout(() => { clearAuth(); showLoginScreen(); }, 2000);
                    return;
                }

                const retryLoadingId = showLoading();
                try {
                    const retryResponse = await sendMessage(lastMessage, config, freshAuth);
                    await processStreamingResponse(retryResponse, retryLoadingId);
                } catch (retryError) {
                    removeLoading(retryLoadingId);
                    addMessage(`Retry failed: ${retryError.message}`, 'ai', { isError: true });
                }
            };
            addMessage(`Sorry, I encountered an error: ${error.message}`, 'ai', {
                isError: true,
                retryCallback: retryFn
            });
        }
    });

    const themeIcon = document.getElementById('themeIcon');
    themeToggle.addEventListener('click', function() {
        document.documentElement.classList.toggle('light');
        const isLight = document.documentElement.classList.contains('light');
        themeIcon.textContent = isLight ? '🌙' : '☀️';
        localStorage.setItem('theme', isLight ? 'light' : 'dark');
    });

    if (localStorage.getItem('theme') === 'dark') {
        document.documentElement.classList.remove('light');
        themeIcon.textContent = '☀️';
    } else {
        document.documentElement.classList.add('light');
        themeIcon.textContent = '🌙';
    }

    logoutBtn.addEventListener('click', function() {
        clearAuth();
        window.location.reload();
    });

    if (uploadBtn && fileInput) {
        uploadBtn.addEventListener('click', () => fileInput.click());
        fileInput.addEventListener('change', (e) => {
            if (e.target.files[0]) handleFileSelect(e.target.files[0]);
        });
    }

    if (clearFileBtn) {
        clearFileBtn.addEventListener('click', clearSelectedFile);
    }

    function showLoginScreen() {
        loginScreen.classList.remove('hidden');
        chatScreen.classList.add('hidden');
        document.getElementById('username').focus();
    }

    function showChatScreen() {
        loginScreen.classList.add('hidden');
        chatScreen.classList.remove('hidden');
        chatScreen.scrollTop = 0;
        const auth = loadAuth();
        if (auth) {
            userDisplay.textContent = auth.username;
            window.currentUsername = auth.username;
        }
        userInput.focus();
    }
});
