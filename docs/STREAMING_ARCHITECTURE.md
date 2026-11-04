# Mecânica de streaming do CINESHOW

A experiência será reconstruída em camadas:

1. **Catálogo**: busca, categorias, detalhes, temporadas e episódios.
2. **Resolver de fonte**: recebe um conteúdo autorizado e obtém a URL de reprodução.
3. **Player**: reproduz HLS ou MP4, com tela cheia, controles e tratamento de erro.
4. **Progresso**: salva posição periodicamente e alimenta “Continuar assistindo”.
5. **Biblioteca do usuário**: favoritos, histórico e downloads quando houver suporte.
6. **Sincronização**: uma API própria poderá substituir os gateways locais sem alterar a interface.

O repositório já contém as abstrações de catálogo, resolução de fonte e progresso. A próxima etapa é conectar uma fonte real autorizada e adicionar o player Flutter.

Não serão incorporados anúncios invasivos, rastreadores, certificados inseguros, credenciais embutidas ou mecanismos para contornar DRM e controle de acesso.

## Ao Vivo e reprodução integrada

A aba Ao Vivo consulta `channels.json`, `streams.json` e `logos.json` da API
pública iptv-org. Exibe somente canais com transmissão HTTP(S), com Brasil como
filtro inicial, todos os países, categorias, busca, favoritos e escolha manual
de fontes. As listas são montadas por ID do canal, sem duplicar URLs; a última
resposta válida fica salva para falhas de conexão. A atualização é manual ou ao
abrir a aba. Os vídeos são reproduzidos diretamente da origem, sem proxy de vídeo.

O player nativo recebe `stream_url` e `stream_headers`, oferece pausa, tela cheia,
carregamento e nova tentativa. Conteúdo sob demanda preserva progresso e permite
avançar; canais ao vivo não salvam posição nem retomam uma posição antiga.
Os parâmetros Referer e User-Agent da API são encaminhados ao reprodutor.
Restrições geográficas, formatos não suportados e indisponibilidade da origem
continuam sendo limitações da transmissão; a lista não é uma garantia de reprodução.

O catálogo existente contém páginas de provedores, não endereços diretos de vídeo.
O botão “Assistir no app · player da fonte” abre a página original em uma WebView,
incluindo seu próprio player e interface. Não transforma a página em stream nativo;
a compatibilidade depende do provedor. “Abrir na fonte” continua disponível.
Quando `stream_url` estiver configurado no catálogo, “Assistir no CINESHOW” abre
o player nativo. Episódios também abrem sua página dentro do app.

Validação em dispositivo: testar canal brasileiro, troca de fonte, erro de rede,
pausa ao sair do app, rotação e tela cheia; testar uma página de filme e episódio
em cada provedor. A compatibilidade dos players de terceiros requer Android real.

## Compatibilidade de canais (0.3.1)

Ao Vivo utiliza media_kit/libmpv para identificar o conteúdo da transmissão,
incluindo MPEG-TS contínuo em URLs sem extensão, HLS e formatos de áudio/vídeo
suportados pelas bibliotecas embarcadas. O player de filmes com link direto
continua separado. O modo compatível desativa a decodificação por hardware.

Ao falhar ou ficar sem progresso, o player tenta as outras fontes do mesmo canal,
sem misturar afiliadas ou canais. Cada tentativa mantém os cabeçalhos específicos
daquela fonte. A inicialização tem limite de 35 segundos até a primeira imagem;
a detecção de interrupção fica suspensa quando o app está em segundo plano ou
quando a reprodução está pausada. Fontes podem ser selecionadas manualmente.
Os erros são diferenciados e os detalhes técnicos omitem URLs completas e tokens.

Diagnóstico em 04/11/2026 a partir do ambiente de desenvolvimento: a fonte Morena
de RedeGlobo.br retornou HTTP 404; outras fontes retornaram HTTP 403. As URLs sem
extensão de TVGloboBrasilia.br e GloboNews.br responderam HTTP 200, video/mp2t.
FFprobe identificou H.264 Main 852x480 e AAC-LC na fonte Brasília. Isso comprova
resposta de rede e formato; não comprova reprodução no Android nem reproduz
exatamente o teste externo do usuário. Não foram alterados certificados,
credenciais ou controles de acesso. Ainda é necessário testar a mesma fonte no
mesmo aparelho e rede para confirmar o caso específico reportado.

## Controles, capas e fontes (0.3.2)

O player nativo compartilha controles com barra de busca, prévia do tempo durante
arraste, início, retrocesso/avanço de 10 segundos e tela cheia. Os controles somem
após três segundos de reprodução e voltam ao toque, inclusive em tela cheia.
Durante pausa e arraste permanecem acessíveis. A TV ao vivo só oferece a barra
quando o backend informa que a fonte aceita busca e fornece duração positiva;
transmissões sem DVR continuam ao vivo. O CINESHOW não grava retroativamente uma
programação que a origem não oferece. Players dentro de páginas WebView mantêm
os próprios controles do provedor; o app permite a apresentação HTML5 em tela
cheia no Android e preserva sessões de iframes com cookies de terceiros.

O catálogo embarcado tinha 93 de 99 itens com poster_url, em sua maioria nos
antigos domínios das fontes. As URLs testadas responderam 403; o mesmo arquivo de
arte 62vtHEyzKhFRuEOLLiQfPi60mSs.jpg respondeu 200 no CDN de imagens TMDB. Para
nomes de arquivo compatíveis, o app tenta o mesmo identificador de arte no CDN,
depois o domínio atual e a URL original. Não há correspondência por título nem
substituição por imagem genérica de outro filme. Capas alternativas por fonte
sobrevivem ao cache; atributos lazy e imagens relativas também são aceitos.

Os destinos observados dos antigos domínios foram casasdefilmes.com (Pobreflix)
e filmevdeizle.com (TopFlix). A migração usa uma lista explícita de aliases;
domínios desconhecidos não são convertidos. Catálogo e páginas continuam sujeitos
à disponibilidade desses terceiros e às mudanças frequentes de endereço.

RedeCanais foi analisado em redecanais.by: a página de um título expõe iframe e
código de incorporação embed.php?vid=..., com player carregado via JavaScript.
Isso permite avaliar incorporação, mas não fornece garantia de ausência de
anúncios nem comprova uma API de reprodução direta. Não foi adicionado ao catálogo
como fonte supostamente livre de anúncios. Não foram alterados bloqueios de
acesso ou sequências exigidas pelo provedor. O app não pode oferecer controles
nativos sobre um iframe que não fornece integração para isso.

## Redirecionamentos de página (0.3.3)

A captura enviada pelo usuário mostrou uma navegação principal do filme para
interlinecustomroofingllc.com, encerrada com ERR_CONNECTION_REFUSED. A WebView
aceitava qualquer URL HTTP(S) no quadro principal; o botão de nova tentativa
recarregava a URL atual, inclusive depois de um desvio externo.

A política agora mantém a navegação principal na origem inicial ou em aliases
explicitamente conhecidos do mesmo provedor. Iframes HTTP(S) de terceiros
continuam permitidos para preservar o player incorporado; o recurso não é um
bloqueador universal de anúncios ou de solicitações de mídia. URLs externas não
se tornam destino de nova tentativa. Recarregar usa a última página permitida.
Erros da página principal usam a interface do app, sem mostrar a página de erro
interna do Android WebView. A abertura externa continua uma ação explícita.

Os testes reproduzem o endereço externo da captura, distinguem iframe e quadro
principal, validam migrações conhecidas e verificam o destino de nova tentativa.
A validação da reprodução de O Fim da Rua na rede/aparelho do usuário ainda é
necessária; a correção da navegação não prova que a fonte liberou o vídeo.
