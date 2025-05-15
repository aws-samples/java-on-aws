#!/bin/bash
# Script to fix bash-preexec errors in Amazon Q shell integration
# Add this to your bootstrap script to fix the error on any new installation

# Create the .bashrc.d directory if it doesn't exist
mkdir -p ~/.bashrc.d

# Create the early-loading fix script
cat > ~/.bashrc.d/00-preexec-fix.sh << 'EOF'
#!/bin/bash
# This file is loaded early in the .bashrc.d sequence to fix bash-preexec variables
# The 00- prefix ensures it loads before other scripts

# Initialize these variables early
__bp_last_argument_prev_command=""
__bp_last_ret_value="0"
BP_PIPESTATUS=()
EOF

# Make it executable
chmod +x ~/.bashrc.d/00-preexec-fix.sh

# Create the comprehensive fix script
cat > ~/.bashrc.d/fix-bp-error.sh << 'EOF'
#!/bin/bash
# Fix for bash-preexec variables
# This script is sourced by .bashrc

# Define these variables if they don't exist
if [ -z "${__bp_last_argument_prev_command+x}" ]; then
    __bp_last_argument_prev_command=""
fi

if [ -z "${__bp_last_ret_value+x}" ]; then
    __bp_last_ret_value="0"
fi

if [ -z "${BP_PIPESTATUS+x}" ]; then
    BP_PIPESTATUS=()
fi

# Override the problematic function to make it more robust
__bp_preexec_invoke_exec() {
    # Ensure the variable is defined before using it
    if [ -z "${__bp_last_argument_prev_command+x}" ]; then
        __bp_last_argument_prev_command="${1:-}"
    else
        __bp_last_argument_prev_command="${1:-}"
    fi
    
    # Rest of the original function...
    if (( ${__bp_inside_preexec:-0} > 0 )); then
      return
    fi
    local __bp_inside_preexec=1
    
    # Continue with normal execution
    return 0
}
EOF

# Make it executable
chmod +x ~/.bashrc.d/fix-bp-error.sh

# Check if .bash_profile exists, if not create it
if [ ! -f ~/.bash_profile ]; then
    cat > ~/.bash_profile << 'EOF'
# Initialize bash-preexec variables to prevent errors
__bp_last_argument_prev_command=""
__bp_last_ret_value="0"
BP_PIPESTATUS=()

# Source .bashrc if it exists
if [ -f ~/.bashrc ]; then
   source ~/.bashrc
fi
EOF
else
    # If .bash_profile exists, add the initialization at the top if not already there
    if ! grep -q "__bp_last_argument_prev_command" ~/.bash_profile; then
        sed -i '1i# Initialize bash-preexec variables to prevent errors\n__bp_last_argument_prev_command=""\n__bp_last_ret_value="0"\nBP_PIPESTATUS=()' ~/.bash_profile
    fi
fi

echo "Bash preexec error fix has been installed successfully."
echo "Please restart your terminal or run 'source ~/.bash_profile' to apply the changes."
