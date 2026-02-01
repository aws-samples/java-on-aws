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

    if (uploadBtn) {
        if (isAttachmentsEnabled(config)) {
            uploadBtn.classList.remove('hidden');
        } else {
            uploadBtn.classList.add('hidden');
            userInput.classList.add('rounded-l-lg');
        }
    }

    const loginMessage = document.getElementById('loginMessage');
    if (loginMessage) {
        if (config.authType === 'simple') {
            loginMessage.textContent = 'Local Mode - Enter any username to continue';
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

        addMessage(message, 'user');
        userInput.value = '';

        const auth = loadAuth();
        if (!auth || Date.now() >= (auth.expiresAt - 300000)) {
            addMessage('Your session has expired. Please log in again.', 'ai', { isError: true });
            setTimeout(() => {
                clearAuth();
                showLoginScreen();
            }, 2000);
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
                const errorMsg = messageContainer.lastElementChild;
                if (errorMsg) errorMsg.remove();

                const freshAuth = loadAuth();
                if (!freshAuth || Date.now() >= (freshAuth.expiresAt - 300000)) {
                    addMessage('Your session has expired. Please log in again.', 'ai', { isError: true });
                    setTimeout(() => {
                        clearAuth();
                        showLoginScreen();
                    }, 2000);
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
        const html = document.documentElement;
        html.classList.toggle('dark');
        themeIcon.textContent = html.classList.contains('dark') ? '☀️' : '🌙';
        localStorage.setItem('theme', html.classList.contains('dark') ? 'dark' : 'light');
    });

    if (localStorage.getItem('theme') === 'dark') {
        document.documentElement.classList.add('dark');
        themeIcon.textContent = '☀️';
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

        const auth = loadAuth();
        if (auth) {
            userDisplay.textContent = auth.username;
            window.currentUsername = auth.username;
        }
        userInput.focus();
    }
});
