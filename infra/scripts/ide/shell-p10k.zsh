# Instant prompt - makes prompt appear instantly while zsh loads
typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet

# Left prompt: directory, git status, prompt symbol
typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(dir vcs newline prompt_char)

# Right prompt: status, duration, jobs, k8s context, aws profile
typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status command_execution_time background_jobs kubecontext aws newline)

# Visual style
typeset -g POWERLEVEL9K_MODE=powerline
typeset -g POWERLEVEL9K_PROMPT_ADD_NEWLINE=true
typeset -g POWERLEVEL9K_LEFT_SEGMENT_SEPARATOR='\uE0B0'
typeset -g POWERLEVEL9K_RIGHT_SEGMENT_SEPARATOR='\uE0B2'
typeset -g POWERLEVEL9K_LEFT_SUBSEGMENT_SEPARATOR='\uE0B1'
typeset -g POWERLEVEL9K_RIGHT_SUBSEGMENT_SEPARATOR='\uE0B3'
# Right frame decoration (disabled for cleaner look)
# typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_SUFFIX='%240F─╮'
# typeset -g POWERLEVEL9K_MULTILINE_NEWLINE_PROMPT_SUFFIX='%240F─┤'
# typeset -g POWERLEVEL9K_MULTILINE_LAST_PROMPT_SUFFIX='%240F─╯'

# Prompt char: green on success, red on error
typeset -g POWERLEVEL9K_PROMPT_CHAR_BACKGROUND=
typeset -g POWERLEVEL9K_PROMPT_CHAR_LEFT_LEFT_WHITESPACE=''
typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=76
typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=196
typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIINS_CONTENT_EXPANSION='❯'

# Remove segment separator after prompt_char (no trailing powerline arrow)
typeset -g POWERLEVEL9K_PROMPT_CHAR_LEFT_SEGMENT_SEPARATOR=''

# Directory
typeset -g POWERLEVEL9K_DIR_BACKGROUND=189
typeset -g POWERLEVEL9K_DIR_FOREGROUND=250
typeset -g POWERLEVEL9K_SHORTEN_STRATEGY=truncate_to_unique
typeset -g POWERLEVEL9K_DIR_MAX_LENGTH=80

# Git status - Palenight colors: green=clean, yellow=modified, red=conflicts
typeset -g POWERLEVEL9K_VCS_CLEAN_BACKGROUND=114
typeset -g POWERLEVEL9K_VCS_CLEAN_FOREGROUND=250
typeset -g POWERLEVEL9K_VCS_MODIFIED_BACKGROUND=221
typeset -g POWERLEVEL9K_VCS_MODIFIED_FOREGROUND=250
typeset -g POWERLEVEL9K_VCS_UNTRACKED_BACKGROUND=114
typeset -g POWERLEVEL9K_VCS_UNTRACKED_FOREGROUND=250
typeset -g POWERLEVEL9K_VCS_CONFLICTED_BACKGROUND=204
typeset -g POWERLEVEL9K_VCS_CONFLICTED_FOREGROUND=250
typeset -g POWERLEVEL9K_VCS_BACKENDS=(git)

# Command execution time: show if > 3 seconds - Palenight muted yellow
typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=3
typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_PRECISION=0
typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FOREGROUND=250
typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_BACKGROUND=221

# Kubernetes context
typeset -g POWERLEVEL9K_KUBECONTEXT_FOREGROUND=250
typeset -g POWERLEVEL9K_KUBECONTEXT_BACKGROUND=189
# Shorten EKS ARN: arn:aws:eks:region:account:cluster/name -> region:cluster-name
typeset -g POWERLEVEL9K_KUBECONTEXT_CONTENT_EXPANSION='${${P9K_KUBECONTEXT_NAME#arn:aws:eks:}%%:*}:${P9K_KUBECONTEXT_CLUSTER##*/}'

# AWS profile: show only when using aws commands - Palenight coral
typeset -g POWERLEVEL9K_AWS_SHOW_ON_COMMAND='aws|terraform|cdk|sam'
typeset -g POWERLEVEL9K_AWS_FOREGROUND=0
typeset -g POWERLEVEL9K_AWS_BACKGROUND=209

# Status: show only on error - Palenight soft red
typeset -g POWERLEVEL9K_STATUS_OK=false
typeset -g POWERLEVEL9K_STATUS_ERROR=true
typeset -g POWERLEVEL9K_STATUS_ERROR_FOREGROUND=0
typeset -g POWERLEVEL9K_STATUS_ERROR_BACKGROUND=204

# Background jobs - Palenight cyan
typeset -g POWERLEVEL9K_BACKGROUND_JOBS_VERBOSE=false
typeset -g POWERLEVEL9K_BACKGROUND_JOBS_FOREGROUND=0
typeset -g POWERLEVEL9K_BACKGROUND_JOBS_BACKGROUND=116
