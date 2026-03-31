# Update terminal input display
# This takes the old PS1 and sticks a single-quoted string onto the end of it
PS1='\[\e[34m\]\w\[\e[0m\]\n\[\e[35m\]➜ '
# PS0: This resets the color to default [0m] the moment you hit Enter
export PS0='\[\e[0m\]'

export PATH="$HOME/.local/bin:$PATH"
export ENABLE_LSP_TOOL=1
