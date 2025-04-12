#!/bin/zsh

# Check if required tools are installed
(( ! $+commands[fzf] )) && return
(( ! $+commands[curl] )) && return

# Check if if OpenAi API key ist set
(( ! ${+ZSH_AI_COMMANDS_OPENAI_API_KEY} )) && echo "zsh-ai-commands::Error::No API key set in the env var ZSH_AI_COMMANDS_OPENAI_API_KEY. Plugin will not be loaded" && return

(( ! ${+ZSH_AI_COMMANDS_HOTKEY} )) && typeset -g ZSH_AI_COMMANDS_HOTKEY='^o'

(( ! ${+ZSH_AI_COMMANDS_LLM_NAME} )) && typeset -g ZSH_AI_COMMANDS_LLM_NAME='best'

(( ! ${+ZSH_AI_COMMANDS_N_GENERATIONS} )) && typeset -g ZSH_AI_COMMANDS_N_GENERATIONS=5

(( ! ${+ZSH_AI_COMMANDS_HISTORY} )) && typeset -g ZSH_AI_COMMANDS_HISTORY=false

fzf_ai_commands() {
  setopt extendedglob

  [ -n "$BUFFER" ] || { echo "Empty prompt" ; return }

  BUFFER="$(echo "$BUFFER" | sed 's/^AI_ASK: //g')"

  ZSH_AI_COMMANDS_USER_QUERY=$BUFFER

  if [ $ZSH_AI_COMMANDS_HISTORY = true ]
  then
    # save to history
    echo "AI_ASK: $ZSH_AI_COMMANDS_USER_QUERY" >> $HISTFILE
    # also to atuin's history if installed
    if command -v atuin &> /dev/null;
    then
        atuin_id=$(atuin history start "AI_ASK: $ZSH_AI_COMMANDS_USER_QUERY")
        atuin history end --exit 0 "$atuin_id"
    fi
  fi

  # FIXME: For some reason the buffer is only updated if zsh-autosuggestions is enabled
  BUFFER="Asking $ZSH_AI_COMMANDS_LLM_NAME for a command to do: $ZSH_AI_COMMANDS_USER_QUERY. Please wait..."
  ZSH_AI_COMMANDS_USER_QUERY=$(echo "$ZSH_AI_COMMANDS_USER_QUERY" | sed 's/"/\\"/g')
  zle end-of-line
  zle reset-prompt

  ZSH_AI_COMMANDS_GPT_SYSTEM="You only answer up to $ZSH_AI_COMMANDS_N_GENERATIONS appropriate shell one liner that does what the user asks for. The user is using the $(basename $SHELL) shell and his setup infos are '$(uname --kernel-name --kernel-release --kernel-version)'. You answer using structured output. If your answer uses arguments or flags, you MUST include an md bullet point list of explanations for each.Don't explain self explanatory placeholders like <ip> or <serverport> etc. If you are certain this cannot be done with only a one liner, you can define reply a shell function declaration instead."

  ZSH_AI_COMMANDS_PARSED=$(llm -m "$ZSH_AI_COMMANDS_LLM_NAME" -s "$ZSH_AI_COMMANDS_GPT_SYSTEM" --schema-multi 'code str, explain str' "$ZSH_AI_COMMANDS_USER_QUERY")

  ZSH_AI_COMMANDS_SUGG_COMMANDS=$(echo $ZSH_AI_COMMANDS_PARSED | jq -r '.["items"][]["code"]')
  ZSH_AI_COMMANDS_SUGG_EXPLANATION=$(echo $ZSH_AI_COMMANDS_PARSED | jq -r '.["items"][]["explain"]')
  
  export ZSH_AI_COMMANDS_SUGG_COMMENTS  # otherwise fzf can't access it
  ZSH_AI_COMMANDS_SELECTED=$(echo $ZSH_AI_COMMANDS_SUGG_COMMANDS | fzf --reverse --height=~100% --preview-window down:wrap --preview 'echo "$ZSH_AI_COMMANDS_SUGG_COMMENTS" | sed -n "$(({n}+1))"p | sed "s/;/\n/g" | sed "s/^\s*//g;s/\s*$//g"')


  # get the answers
  BUFFER=$ZSH_AI_COMMANDS_SELECTED

  zle end-of-line
  zle reset-prompt
  return $ret
}

autoload fzf_ai_commands
zle -N fzf_ai_commands

bindkey $ZSH_AI_COMMANDS_HOTKEY fzf_ai_commands
