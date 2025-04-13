#!/bin/zsh

# Only check for required tools when being sourced
if [[ ${(%):-%N} == zsh-ai-commands.zsh ]]; then
  # Check if required tools are installed
  (( ! $+commands[fzf] )) && echo "fzf is not installed" && return 1
  (( ! $+commands[jq] )) && echo "jq is not installed" && return 1
  (( ! $+commands[jj] )) && echo "jj is not installed, it is used as a fallback for jq. Install it from 'https://github.com/tidwall/jj/releases'" && return 1
fi

(( ! ${+ZSH_AI_HOTKEY} )) && typeset -g ZSH_AI_HOTKEY='^o'

(( ! ${+ZSH_AI_LLM_NAME} )) && typeset -g ZSH_AI_LLM_NAME='best'

(( ! ${+ZSH_AI_N_GENERATIONS} )) && typeset -g ZSH_AI_N_GENERATIONS=5

(( ! ${+ZSH_AI_HISTORY} )) && typeset -g ZSH_AI_HISTORY=true

fzf_ai_commands() {
  setopt extendedglob

  [ -n "$BUFFER" ] || { echo "Empty prompt" ; return 1 }

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

  ZSH_AI_GPT_SYSTEM="You only answer up to $ZSH_AI_N_GENERATIONS appropriate shell one liner that does what the user asks for. The user is using the $(basename $SHELL) shell and his setup infos are '$(uname --kernel-name --kernel-release --kernel-version)'. You answer using structured output. If your answer uses arguments or flags, you MUST include a short paragraph to explain each (do omit self explanatory placeholders like <ip> or <serverport>). Be careful to properly escape things because I will parse your answer expecting json, especially newlines, pipes, etc. Your code can only be one liners otherwise my parsing of your output will fail! So only use a single paragraph without newlines in your explainer. For the explainer you can specify newlines using '<br>' though, I will replace them by a newline for readability so you can format one argument per line for example."

  ZSH_AI_PARSED=$(llm -m "$ZSH_AI_LLM_NAME" -s "$ZSH_AI_GPT_SYSTEM" --schema-multi 'json_escaped_code, json_escaped_explain' "$ZSH_AI_USER_QUERY")

  (
      ZSH_AI_SUGG_CODE=$(echo "$ZSH_AI_PARSED" | jq -r '.["items"][]["json_escaped_code"]')
  ) || (
      echo "Code parsing fails using jq so retrying with jj"
      result=""
      i=1
      item=$(echo "$ZSH_AI_PARSED" | jj items.$i.json_escaped_code)
      while [[ -n "$item" ]]; do
          # Add newline if not the first item
          [[ -n "$result" ]] && result+=$'\n'

          # Append the new item
          result+="$item"

          ((i++))
          item=$(echo "$ZSH_AI_PARSED" | jj items.$i.json_escaped_code)
      done
      ZSH_AI_SUGG_CODE="$result"
  )

  export ZSH_AI_PARSED  # otherwise can't be reached by fzf

  (
      ZSH_AI_SELECTED=$(echo "$ZSH_AI_SUGG_CODE" | fzf --reverse --height=~100% --preview-window down:wrap --preview 'echo "$ZSH_AI_PARSED" | jq -r ".[\"items\"][{n}][\"json_escaped_explain\"]" | sed "s/<br>/\n/g" ' )
    ) || (
        echo "Error when invoking fzf, trying with jj instead of jq"
        ZSH_AI_SELECTED=$(echo "$ZSH_AI_SUGG_CODE" | fzf --reverse --height=~100% --preview-window down:wrap --preview 'echo "$ZSH_AI_PARSED" | jj -r .items.{n}.json_escaped_explain | sed "s/<br>/\n/g" ' )
    ) || (
        echo "Error again when invoking fzf with jj, retrying without explainers"
        ZSH_AI_SELECTED=$(echo "$ZSH_AI_SUGG_CODE" | fzf --reverse --height=~100% )
  )

  # get the answers
  BUFFER=$ZSH_AI_SELECTED

  zle end-of-line
  zle reset-prompt
  return 0
}

autoload fzf_ai_commands
zle -N fzf_ai_commands

bindkey $ZSH_AI_HOTKEY fzf_ai_commands
