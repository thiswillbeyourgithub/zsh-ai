# ZSH AI
![zsh-ai-demo](./zsh-ai-demo.gif)

> **Note:** This plugin is based on the original code from [muePatrick/zsh-ai-commands](https://github.com/muePatrick/zsh-ai-commands) which I gradually improved for my personal use.

This plugin helps you find terminal commands by asking AI for suggestions based on your natural language description.

To use it just type what you want to do (e.g. `list all files in this directory`) and hit the configured hotkey (default: `Ctrl+o`).
When the AI responds with its suggestions, use fzf to select the command you want to execute.

## Features

- Lightweight implementation with < 150 lines of zsh code
- Uses [llm](https://llm.datasette.io/) by [@simonw](https://github.com/simonw), which means you can use any LLM from any provider:
  - OpenRouter.ai (giving indirect access to OpenAI, Anthropic, Google Gemini, Meta, etc.)
  - Ollama for local models
  - And many other providers
- Robust LLM response parsing:
  - Uses structured output format for reliable parsing
  - Processes results through jq with jj as a fallback to ensure suggestions are captured
- Each suggestion comes with:
  - The actual command (one-liner)
  - A detailed explanation accessible in the fzf preview pane
- Integrates with [atuin](https://atuin.sh/) if installed:
  - All queries and selected commands are automatically added to atuin history

## Requirements
* [llm](https://llm.datasette.io/) - CLI tool for accessing language models (`pip install llm`)
* [fzf](https://github.com/junegunn/fzf) - Command-line fuzzy finder
* [jq](https://jqlang.github.io/jq/) - JSON processor
* [jj](https://github.com/tidwall/jj) - Alternative JSON processor (used as fallback)

## Installation

### oh-my-zsh

Clone the repository to your oh-my-zsh custom plugins folder:

```sh
git clone https://github.com/thiswillbeyourgithub/zsh-ai ${ZSH_CUSTOM:=~/.oh-my-zsh/custom}/plugins/zsh-ai
```

Enable it in your `.zshrc` by adding it to your plugin list:

```
plugins=(... zsh-ai ...)
```

### Alternative: Direct sourcing

You can also just clone the repository anywhere and source the zsh-ai.zsh file directly in your `.zshrc`:

```sh
git clone https://github.com/thiswillbeyourgithub/zsh-ai ~/.zsh-ai
echo "source ~/.zsh-ai/zsh-ai.zsh" >> ~/.zshrc
```

You'll need to have the llm CLI tool properly configured with your API keys. Follow the instructions at [llm.datasette.io](https://llm.datasette.io/) to set up your preferred AI provider.

## Configuration Variables

| Variable             | Default                                 | Description                                                   |
| -------------------- | --------------------------------------- | ------------------------------------------------------------- |
| `ZSH_AI_HOTKEY`      | `'^o'` (Ctrl+o)                         | Hotkey to trigger the request                                 |
| `ZSH_AI_LLM_NAME`    | `'openrouter/google/gemini-2.5-pro-preview-03-25'` | Language model to use                             |
| `ZSH_AI_N_GENERATIONS` | `5`                                   | Number of command suggestions to generate                     |
| `ZSH_AI_HISTORY`     | `true`                                  | Whether to save queries to shell history                      |
| `ZSH_AI_FZF_OPTIONS` | `"--reverse --height=~100% --preview-window down:wrap"`| Options for fzf display                        |

## Limitations
- LLM requests can be slow to trigger (suggestions for improvements are welcome). I was able to cut the launch time by 60% by creating a venv using `uv venv zsh_ai_llm --python 3.13 && source ./zsh_ai_llm/bin/activate && uv pip install llm` then `export ZSH_AI_LLM_BIN="path/to/zsh_ai_llm/bin/llm`.
- Multiline commands are intentionally not supported as parsing multiline output reliably is challenging
  - This is why the prompt specifically asks for one-liners only
- Help is appreciated for making the plugin faster and more reliable!

## Known Bugs
- [ ] The placeholder message that should be shown while the AI request is running is not always displayed. For many users it only works if `zsh-autosuggestions` is enabled.

## Credits
This plugin was developed with help from [aider.chat](https://github.com/Aider-AI/aider/issues).
