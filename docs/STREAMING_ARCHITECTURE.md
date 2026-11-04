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
