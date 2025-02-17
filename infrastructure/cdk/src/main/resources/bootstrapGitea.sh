dnf install -y nerdctl cni-plugins
mkdir -p /gitea/config /gitea/data

echo '
version: "2"

services:
  gitea:
    image: gitea/gitea:1.23.1-rootless
    restart: always
    volumes:
      - /gitea/data:/var/lib/gitea
      - /gitea/config:/etc/gitea
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "9999:3000"
      - "2222:2222"
' > gitea.yaml

echo "
APP_NAME = Gitea: Git with a cup of tea
RUN_MODE = prod
RUN_USER = git
WORK_PATH = /var/lib/gitea

[repository]
ROOT = /var/lib/gitea/git/repositories
ENABLE_PUSH_CREATE_USER = true
DISABLE_HTTP_GIT = false

[repository.local]
LOCAL_COPY_PATH = /var/lib/gitea/tmp/local-repo

[repository.upload]
TEMP_PATH = /var/lib/gitea/uploads

[server]
APP_DATA_PATH = /var/lib/gitea
DOMAIN = $EC2_PRIVATE_IP
SSH_DOMAIN = $EC2_PRIVATE_IP
SSH_CREATE_AUTHORIZED_KEYS_FILE=false
HTTP_PORT = 3000
ROOT_URL = http://$EC2_PRIVATE_IP:9000/gitea
DISABLE_SSH = false
SSH_PORT = 2222
SSH_LISTEN_PORT = 2222
START_SSH_SERVER = true
LFS_START_SERVER = true
OFFLINE_MODE = true

[database]
PATH = /var/lib/gitea/gitea.db
DB_TYPE = sqlite3
HOST = localhost:3306
NAME = gitea
USER = root
PASSWD = 
LOG_SQL = false
SCHEMA = 
SSL_MODE = disable

[indexer]
ISSUE_INDEXER_PATH = /var/lib/gitea/indexers/issues.bleve

[session]
PROVIDER_CONFIG = /var/lib/gitea/sessions
PROVIDER = file

[picture]
AVATAR_UPLOAD_PATH = /var/lib/gitea/avatars
REPOSITORY_AVATAR_UPLOAD_PATH = /var/lib/gitea/repo-avatars

[attachment]
PATH = /var/lib/gitea/attachments

[log]
MODE = console
LEVEL = info
ROOT_PATH = /var/lib/gitea/log

[security]
INSTALL_LOCK = true
SECRET_KEY = 
REVERSE_PROXY_LIMIT = 1
REVERSE_PROXY_TRUSTED_PROXIES = *
PASSWORD_HASH_ALGO = pbkdf2

[service]
DISABLE_REGISTRATION = true
REQUIRE_SIGNIN_VIEW = true
REGISTER_EMAIL_CONFIRM = false
ENABLE_NOTIFY_MAIL = false
ALLOW_ONLY_EXTERNAL_REGISTRATION = false
ENABLE_CAPTCHA = false
DEFAULT_KEEP_EMAIL_PRIVATE = false
DEFAULT_ALLOW_CREATE_ORGANIZATION = true
DEFAULT_ENABLE_TIMETRACKING = true
NO_REPLY_ADDRESS = noreply.localhost

[lfs]
PATH = /var/lib/gitea/git/lfs

[mailer]
ENABLED = false

[cron.update_checker]
ENABLED = false

[repository.pull-request]
DEFAULT_MERGE_STYLE = merge

[repository.signing]
DEFAULT_TRUST_MODEL = committer

" > /gitea/config/app.ini
chown -R 1000:1000 /gitea
sudo nerdctl compose -f gitea.yaml up -d --quiet-pull

# We need to be idempotent and check for locked database
while true; do
    CONTAINER=$(sudo nerdctl compose -f gitea.yaml ps --format json | jq .[].Name) # Name is <folder>-<compose-name>-1

    if [ ! -z "$CONTAINER" ]; then
      STATUS=$(sudo nerdctl exec $CONTAINER -- sh -c "gitea admin user create --username workshop-user --email workshop-user@example.com --password $IDE_PASSWORD 2>&1 || exit 0")
      [[ "$STATUS" =~ .*locked|no\ such\ table.* ]] || break
    fi
    sleep 5;
done

tee -a /etc/caddy/Caddyfile <<EOF
http://$IDE_DOMAIN:9000, http://localhost:9000 {
  handle_path /proxy/9000/* {
    reverse_proxy 127.0.0.1:9999
  }

  handle /* {
    reverse_proxy 127.0.0.1:9999
  }
}
EOF

# We add the handle_path in the cloudfront site
sed -i 's~#GITEA~handle_path /gitea/* { \
    reverse_proxy 127.0.0.1:9999 \
  }~' /etc/caddy/Caddyfile

systemctl restart caddy

sleep 5

sudo -u ec2-user bash -c 'git config --global user.email "workshop-user@example.com"'
sudo -u ec2-user bash -c 'git config --global user.name "Workshop User"'

sudo -u ec2-user bash -c 'touch ~/.ssh/config'
tee /home/ec2-user/.ssh/config <<EOF
Host $EC2_PRIVATE_IP
  User git
  Port 2222
  IdentityFile /home/ec2-user/.ssh/id_rsa
  IdentitiesOnly yes
EOF

sudo -u ec2-user bash -c 'chmod 600 ~/.ssh/*'

PUB_KEY=$(sudo cat /home/ec2-user/.ssh/id_rsa.pub)
TITLE="$(hostname)$(date +%s)"

while [[ $(curl -s -o /dev/null -w "%{http_code}" localhost:9000/) != "200" ]]; do echo "Gitea is not yet available ..." &&  sleep 5; done

curl -X 'POST' \
  "http://workshop-user:$IDE_PASSWORD@localhost:9000/api/v1/user/keys" \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d "{
  \"key\": \"$PUB_KEY\",
  \"read_only\": true,
  \"title\": \"$TITLE\"
}"

tee /etc/profile.d/gitea.sh <<EOF
export GIT_SSH_ENDPOINT="$EC2_PRIVATE_IP:2222"
export GITEA_API_ENDPOINT="http://$EC2_PRIVATE_IP:9000"
export GITEA_EXTERNAL_URL="https://$IDE_DOMAIN/gitea/"
export GITEA_PASSWORD="$IDE_PASSWORD"
export GITEA_USERNAME="workshop-user"
EOF

source /etc/profile.d/gitea.sh
