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
