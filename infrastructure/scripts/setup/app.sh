set -e

APP_NAME=${1:-"unicorn-store-spring"}

mkdir -p ~/environment/${APP_NAME}
rsync -aq ~/java-on-aws/apps/${APP_NAME}/ ~/environment/${APP_NAME} --exclude target --exclude src/test 1>/dev/null
cp -R ~/java-on-aws/apps/dockerfiles ~/environment/${APP_NAME}

echo "Seting up the local git repository ..."
cd ~/environment/${APP_NAME}
git init -b main
git config --global user.email "you@workshops.aws"
git config --global user.name "Your Name"

echo "target" >> .gitignore
echo "*.jar" >> .gitignore
git add . 1>/dev/null
git commit -q -m "initial commit" 1>/dev/null

echo "Building the application ..."
mvn clean package 1> /dev/null

echo "{ \"query\": { \"folder\": \"/home/ec2-user/environment/${APP_NAME}\" } }" > /home/ec2-user/.local/share/code-server/coder.json

echo "App setup is complete."
