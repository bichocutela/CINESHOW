# Catálogo unificado e release

## Aplicativo 0.2.2

O app inclui uma fotografia verificada do catálogo público em `assets/catalog.json`.
Ao abrir, exibe o cache e consulta as três fontes em paralelo. Falhas preservam os
itens anteriores da fonte. Busca DooPlay obtém o nonce da página a cada consulta.
Os detalhes carregam episódios de séries e os capítulos/variantes do Xonados.
O botão Assistir abre o conteúdo dentro do aplicativo. Fontes HTTPS de mídia direta configuradas usam o player nativo com play/pause, linha do tempo, saltos de 10 segundos, volume, velocidade, ajuste de imagem, tela cheia, bloqueio de toques e progresso persistente. Capítulos/episódios têm navegação anterior/próximo quando a lista está disponível.

Os players públicos incorporados das fontes são carregados em WebView, com seleção de servidor e tela cheia. Quando há um elemento HTML video acessível, o app acrescenta controles e salva posição; legendas aparecem quando a fonte fornece faixas. Players em iframes de outra origem podem impedir os controles adicionais e retomada; nesses casos permanecem os controles do próprio fornecedor. Qualidade, áudio e legendas dependem do que a fonte disponibiliza. O navegador só é aberto por escolha explícita no menu.

A aba Categorias organiza por tipo, gênero/categoria informada pela fonte e título. Metadados e capas são coletados com três requisições simultâneas no máximo e armazenados em cache diário. Capas são exibidas quando publicadas; gêneros ausentes ficam identificados como Sem gênero informado. Não são inferidos por título. O início é separado em seções de filmes, séries, novelas e reality shows.

Xonados descobre todos os identificadores publicados nos cards. Os seis nomes confirmados servem de fallback; programas novos usam título/capa publicados ou uma identificação genérica, sem inventar um nome. Não há filtro que descarte IDs novos.
O histórico Xonados percorre lotes sucessivos até a fonte deixar de retornar capítulos anteriores. Séries incluem temporadas e páginas de episódios publicadas. Resultados parciais são exibidos e salvos; falhas são indicadas e podem ser retomadas. URLs de player podem expirar.

Deduplicação inicial: título normalizado, tipo e ano. Isso não substitui revisão de
homônimos; o enriquecimento por IMDb/TMDb deve ser validado antes de unificação automática.
Os resultados de duas fontes não significam servidores de vídeo independentes.

## API opcional

`python -m backend.server` (Python 3.11+ e curl) inicia API de metadados na porta 8080.
`SYNC_SECONDS=600` define intervalo mínimo de 300 segundos. SQLite preserva o último
catálogo por fonte. Endpoints: `/health`, `/v1/catalog`, `/v1/search?q=`,
`/v1/details?provider=&id=`, `/v1/events?after=`. Não há endpoint de URL arbitrária.
Configure `CINESHOW_API_URL` como variável do repositório antes do release para
usar um backend HTTPS hospedado; sem ela o app consulta as fontes diretamente.

**Limites atuais:** API ainda não hospedada; sincronização de catálogo agendada só
acontece com o servidor ativo. Events registra novos títulos após a primeira
fotografia. Não há push de novos capítulos com app fechado nesta versão.
Push exige um serviço ativo, cadastro de dispositivos, preferências e configuração
FCM/APNs. Não há alegação de disponibilidade de vídeo baseada só em uma data listada.
Nenhuma licença de conteúdo é presumida; integração nativa exige permissão da fonte.

## Releases e instalação por cima

Identificador permanente: `com.bichocutela.cineshow`.
Flutter fixado em 3.35.7 para geração reproduzível do projeto Android.
Versão inicial: `0.2.0+2`. Versão atual: `0.2.2+4`; aumente o versionCode em cada release.
Nunca troque applicationId nem chave de assinatura. Instalação por cima preserva os
dados locais quando assinatura e id são iguais e o versionCode aumenta.

Configure Secrets do GitHub Actions, nunca arquivos públicos:
- ANDROID_KEYSTORE_BASE64
- ANDROID_STORE_PASSWORD
- ANDROID_KEY_PASSWORD
- ANDROID_KEY_ALIAS

Faça backup seguro da chave. Se já houver uma versão assinada instalada, use a
chave original: outra assinatura não pode substituir aquela instalação.

Tags `v0.2.0` etc devem coincidir com a versão do pubspec. O workflow valida código,
testes e gera um APK release com assinatura permanente, checksum e release no GitHub.
Sem secrets, publicação para explicitamente. APK de validação em branch é debug;
não é um substituto do APK de release e não deve ser usado como base de upgrades.
O botão Sobre → Verificar atualização consulta o último release final público. Só oferece download quando existe APK oficial com SHA-256. O usuário inicia o download dentro do app; porcentagem e MB acompanham os bytes reais do DownloadManager. O download pode continuar em segundo plano e ser retomado na aba Sobre. Ao concluir com o app em primeiro plano, o APK é verificado (hash, pacote, versão crescente e assinatura igual à instalada) e o instalador Android é aberto.

Na primeira instalação pelo CINESHOW, Android 8+ exige autorização para instalar apps desta fonte; ao voltar com a autorização concedida, o instalador abre. A confirmação final continua sendo do Android, sem instalação silenciosa.

O APK fica apenas em `Android/data/com.bichocutela.cineshow/files/Download/updates/`. Um receiver de `MY_PACKAGE_REPLACED` limpa o arquivo após a atualização confirmada; a abertura do app também verifica essa limpeza. Cancelar ou iniciar outro download remove o download anterior. Se o usuário cancelar o instalador, pode tentar instalar novamente ou excluir o APK na aba Sobre. Arquivos baixados por navegadores na pasta pública Downloads não são apagados pelo app.

A versão 0.2.0 ainda abre o GitHub: é necessário instalar a 0.2.1 uma vez para obter o atualizador interno nas próximas versões. Publique novos releases como pré-lançamento até o APK e checksum estarem anexados; só então marque como release final/mais recente.

As logos oficiais permanecem intactas e seus hashes são verificados durante o build. O Android adiciona somente espaço ao redor do ícone para preservar a arte nas máscaras do launcher.

## Catálogo completo e limites das fontes

A fotografia inicial de 99 títulos não é um limite. Ao abrir, o app percorre os arquivos de filmes e séries de Pobreflix e TopFlix, seguindo os links de próxima página publicados até o fim, sem número máximo fixo de páginas/títulos. As origens canônicas observadas (assistirfilmeshdonline.com e alfandega-filmes.com) são aceitas além dos domínios originais. A varredura usa duas solicitações simultâneas e uma pausa entre lotes. O ponto de continuação e o catálogo são salvos a cada dez páginas e no fim; a próxima abertura retoma a busca. Catálogos completos são revisitados após um dia, e a consulta da página inicial mantém novidades enquanto o arquivo antigo é percorrido.

Catálogo e metadados são carregados progressivamente. O app informa o número de títulos/páginas e não marca uma fonte que falhou como completa. Metadados são salvos em lotes; nomes/gêneros desconhecidos permanecem identificados. A busca inclui todos os resultados já indexados e a busca pública das fontes. Nenhuma mídia é baixada em massa: reprodução é streaming sob demanda. Conteúdo não publicado, removido, indisponível ou bloqueado pela própria fonte não é presumido disponível.
