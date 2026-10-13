# Catálogo unificado e release

## Aplicativo 0.2.0

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
Versão inicial: `0.2.0+2`. A próxima deve ser `0.2.1+3` ou superior.
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
O botão Sobre → Verificar atualização consulta o último release público e abre sua
página quando a versão é mais nova. O Android confirma a instalação; não há instalação
silenciosa. Instalação automática, atualização forçada e downloads offline não estão
implementados.
