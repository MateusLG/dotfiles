
# omarchy

Customizações do Omarchy (meu setup sobre Arch + Hyprland).

- `themes/lg-umbra/` — tema pessoal verde/mata, inclui config de hyprland, cores, ícones, backgrounds, e temas para btop, neovim e vscode
- `themes/lg-abissal/` — tema pessoal azul/fundo do mar (tubarões), mesma estrutura do `lg-umbra`
- `themed/waybar.css.tpl` — template extra processado pelo `omarchy-theme-set-templates` a cada troca de tema, expõe `@accent`, `@color0`..`@color15` etc. pro `waybar/style.css` reagir ao tema (o template padrão só expõe `@foreground` e `@background`). Instalar em `~/.config/omarchy/themed/`.

