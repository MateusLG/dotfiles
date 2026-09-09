---
name: produzir-sprites
description: Use quando um jogo precisar de sprites animados de personagens, criaturas, veículos ou objetos com movimento (personagem novo, clipe novo, refazer animação, trocar identidade visual) e o ambiente tiver Codex com image gen, PixelOver e um agente de computer use. Vale para pedidos curtos como "faz os sprites da X", "anima o Y", "precisa de idle e andar". Não use para cenários estáticos, tiles, UI, ícones, fontes, áudio ou arte procedural gerada por código.
compatibility: Codex com image gen; PixelOver pago (export habilitado) numa máquina com GUI; agente de computer use (Astra 6) para operar o PixelOver; Python com Pillow para recorte e checagens.
---

# Produzir sprites

## Princípio

Três ferramentas, três papéis fixos, e o contrato do jogo escrito antes da primeira imagem. O image gen desenha (âncora e partes). O PixelOver pixeliza, riga e anima, operado pelo Astra 6. Você (Codex ou Claude) escreve o contrato, os pedidos e o briefing, recorta, integra e valida com medição. Ninguém redesenha pixel a pixel, ninguém aciona serviço pago fora dessas três, e o usuário não opera GUI nem explica o fluxo. Ele pede "faz os sprites da X" e recebe atlas, metadados e proveniência.

## Papéis

| Quem | Faz | Não faz |
|---|---|---|
| Você (desenvolvedor) | contrato, pedidos ao image gen, recorte das partes, briefing do Astra, importação, gates, proveniência | desenhar, animar, perguntar ao usuário tamanho, fps ou fluxo |
| Image gen (Codex) | âncora de identidade e folha de partes, em arte limpa | animação quadro a quadro, sprite final |
| Astra 6 no PixelOver | importar partes, shader de pixel e indexação, bones, keyframes, export | escolher tamanho, fps, paleta ou nome; redesenhar |

## Fluxo

0. Contrato → 1. Âncora aprovada → 2. Partes → 3. PixelOver → 4. Integração e gates.

- Ator novo: todas as etapas.
- Clipe novo em ator já rigado: adicione o clipe ao contrato e vá direto à etapa 3, abrindo o projeto salvo do PixelOver. Volte às etapas 1 e 2 só se o clipe exigir parte nova (objeto na mão, roupa, montaria).
- Falhou um gate: volte à etapa que o produziu. Nunca corrija no runtime.
- Refazer a âncora depois de partes ou animação prontas invalida tudo abaixo dela.

## 0. Contrato do jogo

Arquivo `data/sprites.json`, ou o contrato de arte que o jogo já tiver. Se não existir, crie antes de qualquer pedido. Derive `frame_size` e `altura_px` da viewport e da escala do jogo (quantos pixels um adulto ocupa na tela), nunca do personagem que chegou primeiro. Todos os campos abaixo são obrigatórios:

```json
{
  "modo": "hd-para-pixel",
  "frame_size": [32, 48],
  "pivot": [16, 44],
  "baseline": 44,
  "limiar_loop": 0.05,
  "paleta": "data/paleta.json",
  "pastas": {"personagem": "assets/personagens", "criatura": "assets/criaturas", "objeto": "assets/objetos"},
  "pontos": {"mao": "Braco_F"},
  "clipes": {
    "idle": {"frames": 12, "fps": 3.33, "loop": true},
    "andar": {"frames": 12, "fps": 10, "loop": true}
  },
  "atores": {
    "nara": {"tipo": "personagem", "direcao": "direita", "altura_px": 40, "clipes": ["idle", "andar"]}
  }
}
```

- `modo`: `hd-para-pixel` é o padrão. O image gen entrega arte limpa em alta resolução e o PixelOver pixeliza e indexa na exportação. `pixel-nativo` só quando o jogo já tem sprites em pixel nativo que precisam casar; aí o image gen entrega pixel art e o PixelOver só riga.
- `pontos`: pontos nomeados que o jogo prende a algo desenhado por ele (mão que segura vara, lanterna ou arma; boca de peixe), cada um mapeado ao bone que o carrega. Vira um marcador no PixelOver e uma lista de coordenadas por quadro no metadado.
- `direcao`: para onde o ator olha na arte. Ator olhando para a direita da tela: o lado direito anatômico fica voltado para a câmera e é o `_F`; o esquerdo fica atrás, `_T`. Olhando para a esquerda, inverte. Repita a leitura no briefing ("`Braco_F` é o braço direito da Nara").
- `limiar_loop`: fração máxima de pixels que podem diferir entre o último e o primeiro quadro de um clipe em loop, medida sobre a união dos pixels opacos dos dois quadros, não sobre a moldura inteira.
- Clipe novo entra no contrato antes de ser pedido. Velocidade, input, colisão e qualquer regra de gameplay ficam fora deste arquivo.

Quando o jogo não define quadros e fps, use estes valores em vez de perguntar:

| Clipe | frames | fps | loop |
|---|---|---|---|
| idle, sentado, respiração | 12 | 3.33 | sim |
| andar, remar, nadar | 12 | 10 | sim |
| gesto, conversa, esforço | 12 | 4.3 | sim |
| ação única (lançar, acenar, golpe) | 12 | 20 | não |

## Pastas

```
assets/raw/imagegen/<ator>/            ancora.png, partes.png, *-pedido.json, proveniencia.json
assets/raw/imagegen/<ator>/partes/     cabeca.png, tronco.png, braco_f.png, braco_t.png, perna_f.png, perna_t.png, acessorios.png
assets/raw/pixelover/<ator>/           projeto salvo, briefings/NN-<escopo>.md, export/
<pastas[tipo]>/<ator>_<clipe>.png e <ator>_<clipe>.json     contrato de runtime
```

Saídas do image gen e exports nunca são sobrescritos. Refazer gera `ancora-v2.png` e registra o motivo na proveniência. O projeto do PixelOver é arquivo vivo, salvo por cima a cada rodada; o que se preserva é o sha256 dele por rodada na proveniência. Cada rodada do Astra tem um briefing numerado (`01-rig-idle-andar.md`, `02-acenar.md`), nunca reescrito.

## 1. Âncora

Uma imagem por ator: corpo inteiro, pose neutra do jogo (em pé, sentado ou montado, conforme o contrato), vista e `direcao` do jogo, fundo alpha real. Aprovação é sua: compare com o briefing do personagem e escreva em `proveniencia.json`:

```json
"ancora": {"arquivo": "…", "sha256": "…", "veredito": {"aprovada": true, "data": "2026-09-09",
  "silhueta": "ok", "materiais": "ok", "cores_por_regiao": "ok", "proporcao": "ok", "notas": ""}}
```

Só depois disso existe etapa 2.

Prompt em inglês, blocos nesta ordem:

1. `Use case: new character.` Com referência existente, `Use case: identity-preserve. Image1 is the identity lock: <descrição>`.
2. Físico e figurino por material, com a cor nominal da paleta e o hex: `slate-blue wool coat (#4a5d70) with brass buttons (#b8862e), mustard scarf, black boots, white hair in a bun`.
3. Pose, vista e direção exatas. O que o jogo desenha fica fora: `no lantern, no rod, no weapon, no scenery; bare hands in holding position`.
4. Estilo pelo modo. `hd-para-pixel`: `clean flat color regions, hard edges, no gradients, no anti-aliasing, no texture, even lighting, thick readable silhouette`. `pixel-nativo`: `canvas represents exactly <W>×<H> game pixels at large nearest-neighbor scale, deliberate pixel clusters, no anti-aliasing`.
5. Enquadramento: `single character centered, generous transparent margin, truly transparent PNG alpha, never a checkerboard, no text, labels, grid or props`.

## 2. Partes

Uma folha por ator, gerada com a âncora como Image1 e `Use case: identity-preserve`. Peça a menor grade de células iguais que caiba a lista de partes (7 partes cabem em 3×3; células sobrando ficam transparentes), uma parte por célula, na ordem declarada em `partes-pedido.json`: cabeca, tronco, braco_f, braco_t, perna_f, perna_t, acessorios. Cada parte inteira, com a região oculta preenchida (o tronco continua sob o braço), mesma escala e iluminação da âncora, sem rótulos.

Você recorta com Pillow: divide a folha pela grade, `getbbox` em cada célula, salva `partes/<parte>.png`. Confere sobrepondo as partes na âncora. Parte faltando, duplicada ou fora de escala: gere a folha de novo. Não desenhe.

## 3. PixelOver, pelo Astra 6

Escreva `briefings/NN-<escopo>.md` no idioma do projeto, com os valores do contrato preenchidos. Cite menus só quando confirmados na documentação (`Project > Export`); para o resto descreva a ação, não o caminho de menu. O briefing segue a ordem real da ferramenta (docs.pixelover.io):

1. Projeto novo (ou abrir o projeto salvo, se o ator já tem rig). Arrastar todas as partes como imagens separadas; arrastar a âncora como imagem de referência.
2. Selecionar as partes juntas e redimensionar até `altura_px`. Em `hd-para-pixel`, aplicar o shader de pixel art e a indexação com a paleta do jogo. Em `pixel-nativo`, sem shader.
3. Bones com a ferramenta Bone: `Root` com comprimento 0 no `pivot`; depois `Tronco`, `Cabeca`, `Braco_F`, `Braco_T`, `Perna_F`, `Perna_T`. Diga no briefing qual lado anatômico é `_F` e qual é `_T`, conforme a regra de `direcao`. Parentear cada parte sob o bone de mesmo nome na árvore de cena; `acessorios` vai sob o bone da parte que acompanha (cachecol sob `Tronco`, bolsa sob `Tronco`, chapéu sob `Cabeca`). Bone próprio para acessório só se um clipe do contrato exigir movimento independente.
4. Marcadores: para cada entrada de `pontos`, uma imagem de 1 pixel `#ff00ff` parenteada ao bone indicado, na posição do ponto (palma da mão, boca), em camada própria chamada `marcador_<ponto>`. A camada sai em arquivo separado no export e não entra no atlas.
5. Uma animação por clipe do contrato, nome igual à chave do contrato, FPS e duração tais que `fps × duração = frames`. Chaves de posição e rotação no quadro 0 para todos os bones; poses seguintes com REC ligado; loops terminam voltando ao quadro 0. Pés na `baseline` em todo quadro, salvo clipe que declare deslocamento vertical.
6. Salvar o projeto em `assets/raw/pixelover/<ator>/`, na extensão nativa da ferramenta.
7. `Project > Export`: PNG, spritesheet ativado (uma folha por animação), JSON de metadados ativado, camadas separadas ativadas, área igual ao `frame_size`, escala 1:1 no pixel do jogo, fundo transparente, destino `export/`. O nome de cada arquivo carrega o nome da animação e, nas camadas separadas, o nome da camada.
8. Reportar: nome e tamanho real de cada arquivo exportado, quadros por clipe, nome e sha256 do projeto salvo, versão do PixelOver.

Termine o briefing com a tabela de gates da etapa 4. O que faltar no briefing é erro seu, não do Astra.

## 4. Integração e gates

Leia o JSON do export: `frames[].frame{x,y,w,h}`, `frames[].duration` e `meta.frameAnimations[]{name,fps,from,to}`. Para cada clipe: recorte os quadros, monte o atlas horizontal em `frame_size`, localize o pixel `#ff00ff` em cada quadro da camada marcadora e grave em `pontos.<ponto>[i]`. Escreva o JSON ao lado do PNG, com todos estes campos:

```json
{"file": "assets/personagens/nara_idle.png", "frames": 12, "frame_size": [32, 48],
 "pivot": [16, 44], "fps": 3.33, "duration": 3.6, "loop": true,
 "pontos": {"mao": [[23, 30], [23, 30]]},
 "origem": "assets/raw/pixelover/nara/export/idle.json"}
```

Integração termina aqui: atlas, JSON e o ator registrado em `atores` do contrato. Se o jogo já tem um registro de animações (um JSON ou script que lista clipes por ator), acrescente o clipe lá. Se não tem cena nem registro ainda, não crie cena, loader ou controlador para "ter onde colocar"; escreva no relatório que a verificação em engine fica pendente até a cena existir. Quando a cena existe, a verificação é abrir, tocar cada clipe e capturar um quadro.

Gates medidos por script no projeto (Pillow). Nenhum é "no olho":

| Gate | Medida | Falhou, volta a |
|---|---|---|
| Quadros | `to − from + 1` igual a `frames` do contrato, por clipe | 3 |
| Paleta | todo pixel opaco está em `paleta`; alpha é 0 ou 255 | 3 |
| Baseline | linha opaca mais baixa igual a `baseline` em todo quadro, salvo clipe com salto | 3 |
| Enquadramento | nenhum pixel opaco tocando a borda da célula | 3 |
| Loop | pixels que diferem entre último e primeiro quadro, sobre a união dos opacos, abaixo de `limiar_loop`, quando `loop` | 3 |
| Pontos | exatamente um pixel `#ff00ff` por quadro na camada marcadora | 3 |
| Identidade | quadro 0 ampliado 8× lado a lado com a âncora; silhueta, materiais e cor por região; veredito escrito em `proveniencia.clipes.<clipe>` | 1 ou 2 |
| Sem texto ou grade | nenhuma célula com xadrez, rótulo ou linha divisória | 2 |

## Proveniência

Cada pedido ao image gen gera `<peça>-pedido.json`: ferramenta, modo, prompt integral, referências (caminho e sha256), arquivo salvo, sha256, tamanho, data. O `proveniencia.json` do ator agrega os pedidos, o veredito da âncora, um veredito por clipe, e por rodada do Astra: briefing, versão do PixelOver, sha256 do projeto salvo, arquivos exportados. Sem isso a peça não está aprovada.

## Erros comuns

- Tratar a saída do image gen como "referência" e mandar o Astra redesenhar no PixelOver. O image gen entrega a arte; o PixelOver transforma e anima.
- Pedir ao image gen a animação em folha de quadros. A identidade oscila entre células e o conserto vira trabalho manual. Partes e rig existem para isso.
- Rig sobre imagem única. Bones exigem partes separadas com oclusão preenchida.
- Inventar menus do PixelOver. Export é `Project > Export`; o resto se descreve como ação.
- Esquecer o marcador do ponto nomeado e depois chutar a posição da mão no código.
- Misturar velocidade, input e colisão no contrato de arte.
- Tamanho de quadro derivado do personagem ("64×64 porque cabe") em vez da viewport.
- Criar cena, loader, controlador ou input map porque o jogo "não tinha onde registrar". Integração é atlas, metadado e contrato; o resto é outra tarefa.
- Refazer âncora e partes para um clipe que só move bones.

## Sinais de que está saindo do fluxo

"É só uma referência", "gero os quadros direto no image gen, é mais rápido", "a âncora não precisa de aprovação formal", "ajusto o pivô no runtime", "o PixelLab resolveria", "vou perguntar qual tamanho ele quer", "crio uma cena mínima só pra registrar". Todos significam: volte ao contrato e à etapa correspondente.
