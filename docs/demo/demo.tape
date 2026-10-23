# Records docs/assets/demo.gif, docs/assets/render.png and docs/assets/schema-guard.png
# with the local helm and the chart in this repository, no registry pull.
# Run from the repository root: make demo

Output docs/assets/demo.gif

Require helm

Set Shell "bash"
Set FontSize 16
Set Width 1200
Set Height 480
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms
Set WindowBar Colorful
Set BorderRadius 10

Hide
Type `PS1='\[\e[38;5;147m\]$\[\e[0m\] ' && clear` Enter
Sleep 500ms
Show

# One values file, the resources it produces.
Type "helm template api . -f examples/values-api.yaml | grep -E '^kind:'" Sleep 400ms Enter
Sleep 2s

# The secure defaults in the rendered pod spec.
Type "helm template web . -s templates/deployment.yaml | grep -E 'automount|Links|NonRoot|Runtime|Esc|ALL|Only'" Sleep 400ms Enter
Sleep 3s
Screenshot docs/assets/render.png
Sleep 1s

# The schema rejects an unsafe setting at render time.
Type "clear" Enter
Type "helm template bad . --set securityContext.privileged=true" Sleep 400ms Enter
Sleep 2s
Screenshot docs/assets/schema-guard.png
Sleep 3s
