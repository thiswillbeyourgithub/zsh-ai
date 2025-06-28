#!/bin/zsh

set -euo pipefail

(( ! ${+ZSH_AI_HOTKEY} )) && typeset -g ZSH_AI_HOTKEY='^o'

# Only check for required tools when being launched
setup_zsh_ai() {
  if [[ ${(%):-%N} == zsh-ai.zsh ]]; then
    # Check if required tools are installed
    (( ! $+commands[fzf] )) && echo "fzf is not installed" && return 1
    (( ! $+commands[jq] )) && echo "jq is not installed" && return 1
    (( ! $+commands[jj] )) && echo "jj is not installed, it is used as a fallback for jq. Install it from 'https://github.com/tidwall/jj/releases'" && return 1
  fi

  # Define the path to the llm binary, try to find it if not set
  # Check if llm command exists (alias, function, or external)
  if (( ! $+commands[llm] )); then
    echo "llm command not found. Please install llm ('pip install llm')." && return 1
  fi

  # Define the path to the llm binary, try to find it if not set
  # Use 'type -p' to find the executable path, even if aliased
  (( ! ${+ZSH_AI_LLM_BIN} )) && typeset -g ZSH_AI_LLM_BIN=$(type -p llm | cut -d' ' -f3 2>/dev/null)

  # Check if ZSH_AI_LLM_BIN was found and points to an executable
  if [[ -z "$ZSH_AI_LLM_BIN" || ! -x "$ZSH_AI_LLM_BIN" ]]; then
    # If type -p failed, llm might be a function or alias without a direct executable path
    # Or the found path is not executable
    # We still need an executable for the script to call
    echo "Could not find an executable path for llm at '$ZSH_AI_LLM_BIN'. If llm is an alias or function, ensure it ultimately calls an executable llm command."
    echo "Alternatively, set the ZSH_AI_LLM_BIN environment variable manually to the llm executable path." && return 1
  fi

  (( ! ${+ZSH_AI_LLM_NAME} )) && typeset -g ZSH_AI_LLM_NAME='openrouter/google/gemini-2.5-pro-preview'

  (( ! ${+ZSH_AI_N_GENERATIONS} )) && typeset -g ZSH_AI_N_GENERATIONS=5

  (( ! ${+ZSH_AI_HISTORY} )) && typeset -g ZSH_AI_HISTORY=true

  (( ! ${+ZSH_AI_FZF_OPTIONS} )) && typeset -g ZSH_AI_FZF_OPTIONS="--reverse --height=~100% --preview-window down:wrap"
}

# Save a query to history with ZSH_AI prefix
zsh_ai_save_to_history() {
  if [ $ZSH_AI_HISTORY = true ]
    then
    local query="$1"
    # save to history
    echo "ZSH_AI: $query" >> $HISTFILE
    # also to atuin's history if installed
    if command -v atuin &> /dev/null;
    then
        atuin_id=$(atuin history start "ZSH_AI: $query")
        atuin history end --exit 0 "$atuin_id"
    fi
  fi
}


fzf_ai_commands() {
  setopt extendedglob

  setup_zsh_ai

  BUFFER="$(echo "$BUFFER" | sed 's/^ZSH_AI: //g' | sed 's/^SUGG: //g'| sed 's/^SELEC: //g')"

  [ -n "$BUFFER" ] || { echo "Empty prompt" ; return 1 }

  ZSH_AI_USER_QUERY="$BUFFER"

  zsh_ai_save_to_history "$ZSH_AI_USER_QUERY"

  # FIXME: For some reason the buffer is only updated if zsh-autosuggestions is enabled
  BUFFER="Asking $ZSH_AI_LLM_NAME for a command to do: $ZSH_AI_USER_QUERY. Please wait..."
  ZSH_AI_USER_QUERY=$(echo "$ZSH_AI_USER_QUERY" | sed 's/"/\\"/g')
  zle end-of-line
  zle reset-prompt

  ZSH_AI_GPT_SYSTEM="You only answer up to $ZSH_AI_N_GENERATIONS appropriate shell one liner that does what the user asks for. The user is using the $(basename $SHELL) shell and his setup infos are '$(uname --kernel-name --kernel-release --kernel-version)'. Today's date is '$(date "+%Y-%m-%d (%A, %B %d, %Y)")'. You answer using structured output. If your answer uses arguments or flags, you MUST include a short paragraph to explain each (do omit self explanatory placeholders like <ip> or <serverport>). Be careful to properly escape things because I will parse your answer expecting json, especially newlines, pipes, etc. Your code can only be one liners otherwise my parsing of your output will fail! So only use a single paragraph without newlines in your explainer. For the explainer you can specify newlines using '<br>' though, I will replace them by a newline for readability so you can format one argument per line for example. Phrase it as military documentation, so very much to the point (i.e. don't start by 'this command blabla')"

  # Call the llm binary using the configured path
  echo "\nCalling llm..."
  ZSH_AI_PARSED=$("$ZSH_AI_LLM_BIN" -m "$ZSH_AI_LLM_NAME" -s "$ZSH_AI_GPT_SYSTEM" --schema-multi 'json_escaped_code, json_escaped_explanation' "$ZSH_AI_USER_QUERY")
  echo "\nParsing llm anser..."

  # remove characters until it starts with { and ends with }
  temp=${ZSH_AI_PARSED#*\{}
  # Add back the {
  temp="{"$temp
  # Remove everything after last }
  ZSH_AI_PARSED=${temp%\}*}"}"

  # Try with jq first
  ZSH_AI_SUGG_CODE=$(echo "$ZSH_AI_PARSED" | jq -r '.["items"][]["json_escaped_code"]' 2>/dev/null)
  
  # If jq failed or returned empty, try with jj
  if [[ $? -ne 0 || -z "$ZSH_AI_SUGG_CODE" ]]; then
    echo "Code parsing fails using jq so retrying with jj"
    result=""
    i=1
    item=$(echo "$ZSH_AI_PARSED" | jj items.$i.json_escaped_code 2>/dev/null)
    while [[ $? -eq 0 && -n "$item" ]]; do
      # Add newline if not the first item
      [[ -n "$result" ]] && result+=$'\n'
      
      # Append the new item
      result+="$item"
      
      ((i++))
      item=$(echo "$ZSH_AI_PARSED" | jj items.$i.json_escaped_code 2>/dev/null)
    done
    
    # Only set if we got results
    [[ -n "$result" ]] && ZSH_AI_SUGG_CODE="$result"
  fi
  
  # If we still don't have code suggestions, show error and exit
  if [[ -z "$ZSH_AI_SUGG_CODE" ]]; then
    echo "Failed to parse AI suggestions. Please try again."
    BUFFER="$ZSH_AI_USER_QUERY"
    return 1
  fi

  export ZSH_AI_PARSED  # otherwise can't be reached by fzf

  # Determine which preview command to use (jq or jj) by testing which one works
  local preview_command
  if echo "$ZSH_AI_PARSED" | jq -r '.["items"][0]["json_escaped_explanation"]' &>/dev/null; then
    preview_command='echo "$ZSH_AI_PARSED" | jq -r ".[\"items\"][{n}][\"json_escaped_explanation\"]" | sed "s/<br>/\n/g"'
  elif echo "$ZSH_AI_PARSED" | jj -r .items.0.json_escaped_explanation &>/dev/null; then
    preview_command='echo "$ZSH_AI_PARSED" | jj -r .items.{n}.json_escaped_explanation | sed "s/<br>/\n/g"'
  else
    # If both fail, use a fallback with no preview
    preview_command='echo "No explanation available"'
  fi

  # Single fzf call with dynamically determined preview command
  ZSH_AI_SELECTED=$(echo "$ZSH_AI_SUGG_CODE" | fzf ${=ZSH_AI_FZF_OPTIONS} --preview "$preview_command")

  # Save all suggestions to history (except the selected one)
  echo "$ZSH_AI_SUGG_CODE" | while read -r line; do
    if [[ -n "$line" && "$line" != "$ZSH_AI_SELECTED" ]]; then
      zsh_ai_save_to_history "SUGG: $line"
    fi
  done
  # Save the selected command to history as most recent
  if [[ -n "$ZSH_AI_SELECTED" ]]; then
    zsh_ai_save_to_history "SELEC: $ZSH_AI_SELECTED"
  fi

  # get the answer only if non empty, otherwise the user exited fzf
  if [[ -n "$ZSH_AI_SELECTED" ]]; then
    BUFFER="$ZSH_AI_SELECTED"
  else
    BUFFER="$ZSH_AI_USER_QUERY"
  fi

  zle end-of-line
  zle reset-prompt
  return 0
}

autoload fzf_ai_commands
zle -N fzf_ai_commands

bindkey $ZSH_AI_HOTKEY fzf_ai_commands
