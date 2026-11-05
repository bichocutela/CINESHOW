# CINESHOW 0.6.1 — verificações e limites

Verificação em 05/11/2026. Mesma assinatura permanente, build 13.

## SuperFlix e Agenda
As duas rotas /lista?category=canais|eventos&format=json&limit=500 retornaram HTTP 200 nesta rede (327 canais brutos e 74 eventos). A causa exata da falha no aparelho não foi reproduzida; a mensagem antiga escondia todos os erros e dizia que havia dados salvos mesmo quando não havia.

A tela agora inicia com diretório real verificado, registra o motivo HTTP/rede/formato, oferece tentar novamente e consulta uma cópia pública independente se a API direta falhar. A cópia tem origem e data explícitas; não é garantia de transmissão nem substitui o player. Canais adultos/inativos são filtrados. O ramo live-data recebe duas listas a cada 30 minutos pelo workflow live-directories; o agendamento do GitHub pode atrasar. O último recurso são as listas incluídas no APK, identificadas pela data de coleta. Nenhum token ou campo play_event_direct_url é publicado na cópia.

## TV Aberta Online
Origem verificada: https://tvabertaonline.bbroot.com/.
- /json/canais.json: 525 canais, categoria, logo e servidores.
- /json/novelas.json: 125 novelas, capas, temporadas e códigos sp dos capítulos. Cerca de 2,17 MB; análise do catálogo fora da interface e cache local de 30 minutos.
- /json/fallback.json: 147 opções alternativas publicadas.
- /api/get-stream?slug=SLUG: renova os links na abertura; não persistir os tokens retornados.
- /api/get-embed?id=API_ID: retorna link e referer para os itens is_vercel_api. Uma resposta testada apontou error.txt; ela não é declarada como vídeo funcional sem validação.
- A página publica BASE_NOVELAS e /play/CODIGO_SP. Um capítulo ACAND-001 foi validado com HTTP 206 e assinatura MP4 ftyp. O app verifica cada capítulo antes de abrir o player nativo.
- Capas e todos os capítulos publicados permanecem ligados à fonte TV Aberta Online. A paginação de 100 já existente limita a lista construída na tela.
- Links de vídeo não recebem assinatura criada pelo app. O túnel adicional publicado para alguns servidores tvdaia não é replicado: esses canais podem depender de outro servidor alternativo.

## Avaliações e elenco
O app anterior só lia a ficha dt/dd e dois nomes da sugestão IMDb; ignorava os atores itemprop=actor, o campo explícito repimdb e a página de créditos do Rotten Tomatoes.

Agora lê todos os atores desses campos e reúne os nomes das fontes disponíveis que não contradizem o IMDb ID. São separados atores de diretores/equipe; papéis publicados também são preservados. A tela mostra os primeiros 12 e permite abrir todos em uma lista rolável, sem truncar os últimos créditos. O índice de filmes por ator ainda cobre fichas já consultadas no aparelho.

IMDb é apresentado em x,x/10; Tomatometer representa críticos e Popcornmeter representa público. O RT é localizado pela busca publicada com nome, ano e tipo iguais e confirmado por URL canônica/JSON-LD. Porcentagens vêm do media-scorecard-json do próprio título, sem usar os cards de recomendações. A página cast-and-crew fornece os créditos adicionais. Acesso público e layout podem mudar; falhas não geram porcentagens inventadas.

Na verificação, o Pobreflix informou IMDb 8.0 para tt22084616, enquanto a imagem enviada mostra 7.9 no IMDb. O HTTP direto do IMDb respondeu 403 nesta rede; por isso o valor reproduzido pela fonte é identificado como tal e pode estar defasado. Não foi fixado nenhum valor específico no código de produção. Consulta direta/OMDb, quando disponíveis, têm precedência.

## Migração do player
O aviso público em https://redeflixapi.store anuncia https://redeflixapi.bar. Só esse host exato é substituído, preservando caminho, ID, temporada, episódio, parâmetros e fragmento. O novo domínio pode redirecionar para a infraestrutura publicada pelo próprio provedor. Sem chaves de API comerciais nem bypass de verificações.

Validação: testes de parser com campos de fichas reais, distinção entre as três notas, recusa de outro filme/ano, resposta HTTP indisponível, reserva de canais/eventos, preservação da rota migrada, esquema de capítulos da TV Aberta e telas estreitas/lista até o último ator. Não houve teste em aparelho Android físico.
