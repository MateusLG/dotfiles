# waybar

Configurações da Waybar.

- `config.jsonc` — módulos ativos:
  - `cpu` e `memory` à direita, só a porcentagem (sem ícone), ambos com warning/critical
  - `pulseaudio` com ícones escalonados (`󰕿 󰖀 󰕾`) e mudo `󰖁`
  - `custom/kb-layout` mostra o layout atual (US/BR) atualizado a cada 1s
- `style.css` — usa cores do tema atual do Omarchy (`@accent`, `@color1`, `@color3`, etc.) via `@import "../omarchy/current/theme/waybar.css"`. Workspace ativa e `kb-layout` usam `@accent`; indicadores de gravação/idle e estado `critical` de cpu/mem/bateria usam `@color1`.

Para expor as cores do tema pra waybar, este repo instala um template extra em `omarchy/themed/waybar.css.tpl` (aplicado pelo `omarchy-theme-set-templates` a cada troca de tema).
