# Requirements Document

## Introduction

This feature adds ARM64 (Graviton) architecture support to the workshop IDE infrastructure, introduces AWS Code Editor as an alternative to code-server, enhances the extension installation with a comprehensive set for Java workshops, adds Kiro CLI installation, and implements token-based URL access for Workshop Studio integration.

## Glossary

- **ARM64/Graviton**: AWS's ARM-based processors offering better price-performance for many workloads
- **Code Editor**: AWS's VS Code-based IDE for Workshop Studio
- **code-server**: Open-source VS Code server implementation currently used
- **Kiro CLI**: AWS's AI-powered CLI tool for development assistance
- **Workshop Studio**: AWS's platform for hosting interactive workshops
- **Architecture Parameter**: CDK construct parameter that determines whether to use ARM64 or x86_64 instances and binaries

## Requirements

### Requirement 1: Architecture Parameter in CDK

**User Story:** As a workshop administrator, I want to specify the architecture (ARM64 or x86_64) as a CDK parameter, so that instance types and script behavior are automatically derived from this single setting.

#### Acceptance Criteria

1. WHEN the Ide construct is instantiated THEN the System SHALL accept an architecture parameter (ARM64 or X86_64)
2. WHEN architecture is set to ARM64 THEN the System SHALL use Graviton instance types (m7g, m6g families)
3. WHEN architecture is set to X86_64 THEN the System SHALL use Intel/AMD instance types (m7i-flex, m6i, m5 families)
4. WHEN architecture is set THEN the System SHALL pass the architecture value to UserData for script consumption
5. WHEN architecture parameter is not specified THEN the System SHALL default to ARM64

### Requirement 2: Architecture-Aware Script Downloads

**User Story:** As a workshop administrator, I want the IDE scripts to use the architecture from CDK parameter, so that the correct binary versions are downloaded.

#### Acceptance Criteria

1. WHEN the bootstrap scripts execute THEN the System SHALL read the architecture from environment variable set by UserData
2. WHEN downloading kubectl THEN the System SHALL use the architecture-appropriate binary URL (arm64 or amd64)
3. WHEN downloading SAM CLI THEN the System SHALL use the architecture-appropriate zip file (arm64 or x86_64)
4. WHEN downloading eks-node-viewer THEN the System SHALL use the architecture-appropriate binary (arm64 or x86_64)
5. WHEN downloading SOCI snapshotter THEN the System SHALL use the architecture-appropriate tarball (arm64 or amd64)
6. WHEN downloading yq THEN the System SHALL use the architecture-appropriate binary (arm64 or amd64)
7. WHEN downloading Helm THEN the System SHALL use the architecture-appropriate installation

### Requirement 3: AWS Code Editor Installation

**User Story:** As a workshop administrator, I want to install AWS Code Editor alongside code-server, so that I can choose the best IDE option for Workshop Studio integration.

#### Acceptance Criteria

1. WHEN the code-editor.sh script executes THEN the System SHALL download AWS Code Editor from code-editor.amazonaws.com
2. WHEN downloading AWS Code Editor THEN the System SHALL verify the SHA256 checksum against the manifest
3. WHEN installing AWS Code Editor THEN the System SHALL install to the user's ~/.local directory
4. WHEN configuring AWS Code Editor THEN the System SHALL create a systemd service on port 8889 (same as code-server)
5. WHEN configuring AWS Code Editor THEN the System SHALL accept the server license terms automatically
6. WHEN the code-editor.sh script completes THEN the System SHALL configure Caddy to proxy port 8889

### Requirement 4: Extension Installation Enhancement

**User Story:** As a workshop participant, I want the IDE to have all necessary extensions pre-installed and unwanted pre-installed extensions removed, so that I can start coding immediately without distractions.

#### Acceptance Criteria

1. WHEN installing extensions THEN the System SHALL install Java Extension Pack (vscjava.vscode-java-pack)
2. WHEN installing extensions THEN the System SHALL install Docker extension (ms-azuretools.vscode-docker)
3. WHEN installing extensions THEN the System SHALL install Kubernetes extension (ms-kubernetes-tools.vscode-kubernetes-tools)
4. WHEN extension installation fails THEN the System SHALL log the failure and continue with remaining extensions
5. WHEN configuring Code Editor THEN the System SHALL uninstall pre-installed AWS Toolkit extension (AmazonWebServices.aws-toolkit-vscode)
6. WHEN configuring Code Editor THEN the System SHALL uninstall pre-installed Amazon Q extension (AmazonWebServices.amazon-q-vscode)

### Requirement 5: Kiro CLI Installation

**User Story:** As a workshop participant, I want Kiro CLI pre-installed, so that I can use AI-assisted development features.

#### Acceptance Criteria

1. WHEN the bootstrap scripts execute THEN the System SHALL download and install Kiro CLI
2. WHEN Kiro CLI installation completes THEN the System SHALL verify the installation by checking the version
3. IF Kiro CLI installation fails THEN the System SHALL log the error and continue bootstrap

### Requirement 6: Token-Based URL Access

**User Story:** As a workshop administrator, I want the IDE URL to include an authentication token, so that Workshop Studio can provide seamless access.

#### Acceptance Criteria

1. WHEN AWS Code Editor is configured THEN the System SHALL create a token file at ~/.code-editor-server/data/token
2. WHEN the CloudFormation stack outputs the URL THEN the System SHALL include the token parameter (?tkn=xxx)
3. WHEN a user accesses the URL with valid token THEN the System SHALL authenticate automatically

### Requirement 7: CDK Instance Type Lists

**User Story:** As a workshop administrator, I want the CDK to have predefined instance type lists for each architecture, so that the correct instances are used based on the architecture parameter.

#### Acceptance Criteria

1. WHEN architecture is ARM64 THEN the System SHALL use instance types from the ARM64 list (m7g.xlarge, m6g.xlarge, t4g.xlarge)
2. WHEN architecture is X86_64 THEN the System SHALL use instance types from the x86_64 list (m7i-flex.xlarge, m6i.xlarge, m5.xlarge, t3.xlarge)
3. WHEN the CDK code is updated THEN the System SHALL preserve the old instance list as comments for reference
4. WHEN instance launch fails THEN the System SHALL try the next instance type in the architecture-specific list

### Requirement 8: Shared Extension Installation Logic

**User Story:** As a maintainer, I want extension installation logic to be reusable, so that both code-server and AWS Code Editor can use the same code.

#### Acceptance Criteria

1. WHEN installing extensions THEN the System SHALL use a shared function that accepts the IDE binary path as parameter
2. WHEN the shared function is called THEN the System SHALL use retry logic for resilience
3. WHEN the shared function is called THEN the System SHALL support both code-server and code-editor-server binaries
4. WHEN the shared function is called THEN the System SHALL first uninstall unwanted extensions before installing new ones
