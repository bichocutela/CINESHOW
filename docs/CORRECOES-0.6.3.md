# CINESHOW 0.6.3

A tela do ator agora consulta os arquivos de elenco publicados por Pobreflix e TopFlix, além de links de elenco explicitamente encontrados nas fichas compatíveis. O cache serve para exibição imediata e funcionamento parcial sem rede; uma consulta nova ocorre sempre que a tela abre. A paginação mantém o cursor por fonte e permite repetir a fonte que falhou. Não é uma busca textual por nome de ator na busca de títulos, que não assegura os créditos.

Verificados publicamente /melhores-elenco/tom-holland/ nas duas fontes: 16 títulos no corpo principal. Os seis cards na barra lateral são excluídos. O cabeçalho precisa confirmar exatamente o nome do ator antes de qualquer resultado ser atribuído a ele. A lista cobre os catálogos/créditos consultados e pode variar por fonte; não representa a filmografia mundial completa do IMDb.

O SuperFlix publica data-copy=tt... junto ao botão de cópia do IMDb em cada card. Esse ID era ignorado. Agora é preservado em MediaSource, serializado e mesclado com entradas antigas sem perder os identificadores novos. Entradas antigas de SuperFlix também podem recuperar o ID pela busca publicada, exigindo o mesmo identificador de título da fonte.

As fichas DooPlay publicam Título Original em custom_fields, por vezes com o invólucro SEO Watch ... Online. A leitura remove esse invólucro e usa o título original para a busca. Se não houver ID, a sugestão pública IMDb só é aceita com título/alias conhecido, ano e tipo correspondentes e candidato único. Não se escolhe automaticamente o primeiro resultado traduzido sem correspondência verificável. Informações vazias não ficam presas por seis horas: o prazo é reduzido para cinco minutos e a atualização manual continua disponível.

Dados e rotas verificados em 05/11/2026. Sem chave privada adicionada e sem automação de CAPTCHA. As verificações de identidade evitam percentuais de outro filme. As informações ainda dependem do acesso público e dos dados efetivamente publicados; novela ou título sem correspondência confirmada pode não ter avaliação.
