// Authentication management
const AUTH_KEY = 'agentcore_auth';
const SESSION_KEY = 'agentcore_session_id';

let currentAuth = null;

// Session ID management
function getSessionId() {
    let sessionId = sessionStorage.getItem(SESSION_KEY);
    if (!sessionId) {
        sessionId = crypto.randomUUID();
        sessionStorage.setItem(SESSION_KEY, sessionId);
    }
    return sessionId;
}

function clearSessionId() {
    sessionStorage.removeItem(SESSION_KEY);
}

function saveAuth(auth) {
    localStorage.setItem(AUTH_KEY, JSON.stringify(auth));
    currentAuth = auth;
}

function loadAuth() {
    if (currentAuth) return currentAuth;
    const saved = localStorage.getItem(AUTH_KEY);
    if (saved) {
        currentAuth = JSON.parse(saved);
    }
    return currentAuth;
}

function clearAuth() {
    localStorage.removeItem(AUTH_KEY);
    clearSessionId();
    currentAuth = null;
}

function isAuthenticated() {
    const auth = loadAuth();
    if (!auth || !auth.expiresAt || !auth.accessToken) return false;
    return !isSessionExpired(auth);
}

function isSessionExpired(auth) {
    return !auth || Date.now() >= (auth.expiresAt - 300000);
}

async function authenticateUser(username, password, config) {
    return authenticateCognito(username, password, config);
}

async function authenticateCognito(username, password, config) {
    if (typeof AmazonCognitoIdentity === 'undefined') {
        await new Promise((resolve, reject) => {
            const script = document.createElement('script');
            script.src = 'https://cdn.jsdelivr.net/npm/amazon-cognito-identity-js@6.3.6/dist/amazon-cognito-identity.min.js';
            script.onload = resolve;
            script.onerror = () => reject(new Error('Failed to load Cognito SDK'));
            document.head.appendChild(script);
        });
    }

    const normalizedUsername = username.toLowerCase().trim();

    const poolData = {
        UserPoolId: config.userPoolId,
        ClientId: config.clientId
    };

    const userPool = new AmazonCognitoIdentity.CognitoUserPool(poolData);
    const authenticationDetails = new AmazonCognitoIdentity.AuthenticationDetails({
        Username: normalizedUsername,
        Password: password
    });
    const cognitoUser = new AmazonCognitoIdentity.CognitoUser({
        Username: normalizedUsername,
        Pool: userPool
    });

    return new Promise((resolve, reject) => {
        cognitoUser.authenticateUser(authenticationDetails, {
            onSuccess: function(result) {
                const accessToken = result.getAccessToken().getJwtToken();
                const idToken = result.getIdToken().getJwtToken();
                const expiresAt = Date.now() + (result.getAccessToken().getExpiration() * 1000);
                
                let parsedUsername = username;
                try {
                    const payload = JSON.parse(atob(accessToken.split('.')[1]));
                    parsedUsername = payload.username || username;
                } catch (e) {}

                const auth = {
                    username: parsedUsername,
                    accessToken: accessToken,
                    idToken: idToken,
                    expiresAt: expiresAt,
                    authType: 'cognito'
                };

                saveAuth(auth);
                resolve(auth);
            },
            onFailure: function(err) {
                reject(err);
            },
            newPasswordRequired: function() {
                reject(new Error('New password required. Please use AWS Console to set a new password.'));
            }
        });
    });
}
