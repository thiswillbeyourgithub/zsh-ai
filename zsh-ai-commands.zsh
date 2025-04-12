#!/bin/zsh

# Check if required tools are installed
(( ! $+commands[fzf] )) && return
(( ! $+commands[curl] )) && return

(( ! ${+ZSH_AI_HOTKEY} )) && typeset -g ZSH_AI_HOTKEY='^o'

(( ! ${+ZSH_AI_LLM_NAME} )) && typeset -g ZSH_AI_LLM_NAME='best'

(( ! ${+ZSH_AI_N_GENERATIONS} )) && typeset -g ZSH_AI_N_GENERATIONS=5

(( ! ${+ZSH_AI_HISTORY} )) && typeset -g ZSH_AI_HISTORY=true

fzf_ai_commands() {
  setopt extendedglob

  [ -n "$BUFFER" ] || { echo "Empty prompt" ; return }

  BUFFER="$(echo "$BUFFER" | sed 's/^ZSH_AI: //g')"

  ZSH_AI_USER_QUERY=$BUFFER

  if [ $ZSH_AI_HISTORY = true ]
  then
    # save to history
    echo "ZSH_AI: $ZSH_AI_USER_QUERY" >> $HISTFILE
    # also to atuin's history if installed
    if command -v atuin &> /dev/null;
    then
        atuin_id=$(atuin history start "ZSH_AI: $ZSH_AI_USER_QUERY")
        atuin history end --exit 0 "$atuin_id"
    fi
  fi

  # FIXME: For some reason the buffer is only updated if zsh-autosuggestions is enabled
  BUFFER="Asking $ZSH_AI_LLM_NAME for a command to do: $ZSH_AI_USER_QUERY. Please wait..."
  ZSH_AI_USER_QUERY=$(echo "$ZSH_AI_USER_QUERY" | sed 's/"/\\"/g')
  zle end-of-line
  zle reset-prompt

  ZSH_AI_GPT_SYSTEM="You only answer up to $ZSH_AI_N_GENERATIONS appropriate shell one liner that does what the user asks for. The user is using the $(basename $SHELL) shell and his setup infos are '$(uname --kernel-name --kernel-release --kernel-version)'. You answer using structured output. If your answer uses arguments or flags, you MUST include an '-' separated md bullet point list of explanations for each (omit self explanatory placeholders like <ip> or <serverport>). Be careful to properly escape things because I will parse your answer expecting json, especially newlines, pipes, etc. You have to give a one liner otherwise my parsing of your output will fail!"

  # also use sed to replace newlines of json otherwise the parsing fails
  ZSH_AI_PARSED=$(llm -m "$ZSH_AI_LLM_NAME" -s "$ZSH_AI_GPT_SYSTEM" --schema-multi 'code str, explain str' "$ZSH_AI_USER_QUERY" | sed -z 's/\\n-/ZSHNEWLINE- /g')

  ZSH_AI_SUGG_CODE=$(echo "$ZSH_AI_PARSED" | jq -r '.["items"][]["code"]')
  ZSH_AI_SUGG_EXPLAIN=$(echo "$ZSH_AI_PARSED" | jq -r '.["items"][]["explain"]')

  export ZSH_AI_PARSED
  ZSH_AI_SELECTED=$(echo "$ZSH_AI_SUGG_CODE" | fzf --reverse --height=~100% --preview-window down:wrap --preview 'echo "$ZSH_AI_PARSED" | jq -r ".[\"items\"][{n}][\"explain\"]" | sed -z "s/ZSHNEWLINE/\n/g"')

  # get the answers
  BUFFER=$ZSH_AI_SELECTED

  zle end-of-line
  zle reset-prompt
  return $ret
}

autoload fzf_ai_commands
zle -N fzf_ai_commands

bindkey $ZSH_AI_HOTKEY fzf_ai_commands
