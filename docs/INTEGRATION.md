# Catálogo unificado e release

## Aplicativo 0.2.1

O app inclui uma fotografia verificada do catálogo público em `assets/catalog.json`.
Ao abrir, exibe o cache e consulta as três fontes em paralelo. Falhas preservam os
itens anteriores da fonte. Busca DooPlay obtém o nonce da página a cada consulta.
Os detalhes carregam episódios de séries e os capítulos/variantes do Xonados.
A reprodução desta versão abre a fonte original no navegador externo. Um iframe
não é enviado ao player nativo. Reprodução nativa permanece disponível na classe
PlayerPage para URLs de mídia autorizadas, mas não está conectada a esses embeds.

Xonados usa seis identificadores confirmados (1–6). IDs 7 e 8 não são rotulados sem
evidência. Mudanças de nomes/identificadores exigem revisão do conector.
O histórico Xonados inicial inclui o capítulo selecionado e um lote de anteriores;
a lista completa continua disponível na fonte original. URLs de player podem expirar.

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
Versão inicial: `0.2.0+2`. Versão atual: `0.2.1+3`; aumente o versionCode em cada release.
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
