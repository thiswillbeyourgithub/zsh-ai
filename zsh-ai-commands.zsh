#!/bin/zsh

# Check if required tools are installed
(( ! $+commands[fzf] )) && return
(( ! $+commands[curl] )) && return

(( ! ${+ZSH_AI_HOTKEY} )) && typeset -g ZSH_AI_HOTKEY='^o'

(( ! ${+ZSH_AI_LLM_NAME} )) && typeset -g ZSH_AI_LLM_NAME='best'

(( ! ${+ZSH_AI_N_GENERATIONS} )) && typeset -g ZSH_AI_N_GENERATIONS=5

(( ! ${+ZSH_AI_HISTORY} )) && typeset -g ZSH_AI_HISTORY=true

(( ! ${+ZSH_AI_MAX_RETRIES} )) && typeset -g ZSH_AI_MAX_RETRIES=3

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

  ZSH_AI_GPT_SYSTEM="You only answer up to $ZSH_AI_N_GENERATIONS appropriate shell one liner that does what the user asks for. The user is using the $(basename $SHELL) shell and his setup infos are '$(uname --kernel-name --kernel-release --kernel-version)'. You answer using structured output. If your answer uses arguments or flags, you MUST include a text with brief explanations for each (omit self explanatory placeholders like <ip> or <serverport>). NEVER forget to properly escape ALL newlines, pipes, etc in your answer as it will be parsed as indented json! And this applies to both code and explanations! I know this is weird to write md with escaped newlines but you have to."

  # also use sed to replace newlines of json otherwise the parsing fails
  ZSH_AI_PARSED=$(llm -m "$ZSH_AI_LLM_NAME" -s "$ZSH_AI_GPT_SYSTEM" --schema-multi 'json_escaped_code, json_escaped_explain' "$ZSH_AI_USER_QUERY")

  # try to escape any forgotten newline
  ZSH_AI_PARSED=$(echo "$ZSH_AI_PARSED" | sed -z 's/^\([^{}\[\] ]\)/\\n\1/g')

  # Configure max number of retry attempts
  # Array to store error messages
  error_messages=()
  
  # Initial attempt
  success=false
  for attempt in {1..$ZSH_AI_MAX_RETRIES}; do
    if [[ $attempt -eq 1 ]]; then
      # First attempt with original parsed output
      parsed_output="$ZSH_AI_PARSED"
    else
      # Retry attempts with corrected output
      echo "\nAttempt $attempt: Asking the LLM to correct previous errors."
      parsed_output=$(llm -m "$ZSH_AI_LLM_NAME" -s "You gave me an improperly escaped output format for my json pipeline. The errors were: ${(j:, :)error_messages}. Please fix these errors and any other error that could impact the formatting." --schema-multi 'json_escaped_code, json_escaped_explain' "$ZSH_AI_PARSED")
    fi
    
    # Try parsing with jq
    error=$(echo "$parsed_output" | jq '.items' 2>&1)
    if [[ $? -eq 0 ]]; then
      success=true
      break
    else
      # Store error message in array
      error_messages+=("$error")
      echo "\nError parsing answer using jq: '$error'"
    fi
  done
  
  # Handle final result
  if ! $success; then
    echo "\nFailed after $ZSH_AI_MAX_RETRIES attempts. All errors: ${(j:\n:)error_messages}"
    echo "\nHere is the full LLM output:\n$ZSH_AI_PARSED"
    return 1
  else
    ZSH_AI_PARSED=$parsed_output
  fi

  # modify the code output so that it ends with a delimiter for fzf
  ZSH_AI_PARSED=$(echo "$ZSH_AI_PARSED" | jq '.items = (.items | map(.json_escaped_code += "ZSH_AI_END_OF_CODE"))')

  ZSH_AI_SUGG_CODE=$(echo "$ZSH_AI_PARSED" | jq -r '.["items"][]["json_escaped_code"]')

  # otherwise fzf can't reach it
  export ZSH_AI_PARSED
  ZSH_AI_SELECTED=$(echo "$ZSH_AI_SUGG_CODE" | fzf --separator "ZSH_AI_END_OF_CODE" --reverse --height=~100% --preview-window down:wrap --preview 'echo "$ZSH_AI_PARSED" | jq -r ".[\"items\"][{n}][\"json_escaped_explain\"]"')

  # get the answers
  BUFFER=$ZSH_AI_SELECTED

  zle end-of-line
  zle reset-prompt
  return $ret
}

autoload fzf_ai_commands
zle -N fzf_ai_commands

bindkey $ZSH_AI_HOTKEY fzf_ai_commands
