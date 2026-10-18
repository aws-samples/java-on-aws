#!/bin/bash
# Assemble every stage onto a Spring Initializr project and compile it (no AWS calls); then the backoffice
# MCP server (apps/backoffice-java: app/ plus its stages).
# Usage: tests/run.sh [STAGE...]   (default: all stages and the backoffice)
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
curl -sf https://start.spring.io/starter.zip -d type=maven-project -d language=java -d packaging=jar \
  -d javaVersion=25 -d bootVersion=4.1.0 -d baseDir=aiagent -d groupId=com.example -d artifactId=agent \
  -d name=agent -d description='AI agent with Spring AI and Amazon Bedrock' \
  -d dependencies=spring-ai-bedrock-converse,web,webflux,actuator -o "$WORK/aiagent.zip"
STAGES=("$@")
[ ${#STAGES[@]} -gt 0 ] || STAGES=($(python3 -c "import sys; sys.path.insert(0, '$HERE'); import build_stages; print(' '.join(build_stages.STAGES))"))
for stage in "${STAGES[@]}"; do
  rm -rf "$WORK/aiagent" && (cd "$WORK" && unzip -q aiagent.zip)
  python3 "$HERE/build_stages.py" assemble "$stage" "$WORK/aiagent"
  (cd "$WORK/aiagent" && ./mvnw -q -ntp -DskipTests compile) && echo "$stage: ok"
done

[ $# -gt 0 ] && exit 0
# Backoffice: app/ + stages/01-mcp-server (trip tools) + stages/02-expenses (expense package)
BACKOFFICE="$HERE/../backoffice-java"
rm -rf "$WORK/backoffice" && cp -R "$BACKOFFICE/app" "$WORK/backoffice"
cp "$BACKOFFICE/stages/01-mcp-server/pom.xml" "$WORK/backoffice/pom.xml"
cp "$BACKOFFICE/stages/01-mcp-server/application.properties" "$WORK/backoffice/src/main/resources/"
cp "$BACKOFFICE/stages/01-mcp-server/TripTools.java" "$WORK/backoffice/src/main/java/com/example/backoffice/trip/"
mkdir -p "$WORK/backoffice/src/main/java/com/example/backoffice/expense"
cp "$BACKOFFICE"/stages/02-expenses/*.java "$WORK/backoffice/src/main/java/com/example/backoffice/expense/"
find "$WORK/backoffice" -type f \( -name "*.java" -o -name "*.xml" -o -name "*.properties" \) \
  -exec sed -i.bak -E '/^[[:space:]]*(\/\/|#|<!--) (>>|<<)/d' {} \;
find "$WORK/backoffice" -name "*.bak" -delete
"$WORK/aiagent/mvnw" -q -ntp -f "$WORK/backoffice/pom.xml" -DskipTests compile && echo "backoffice: ok"
