# Auditoria do CINESHOW — 0.6.4

Base: a6eaff678bf9aa52ba803304bb310955aad51f60, versão 0.6.3. Data: 05/11/2026.

Escopo: fluxos de catálogo, busca/atores, favoritos, animes, capítulos, progresso e retomada, notificações, downloads e atualização Android. Revisão de código e testes automatizados; não representa teste em aparelho físico nem verificação individual de todas as transmissões de terceiros.

| Problema confirmado no código | Efeito | Correção |
|---|---|---|
| Favoritos guardavam apenas IDs e Minha lista filtrava somente o catálogo da Home | Um título encontrado por ator, busca ou Anime podia não aparecer na lista ou sumir ao reiniciar | Snapshot completo por favorito, migração dos IDs antigos quando seus dados estão disponíveis e gravações serializadas |
| MediaItem.fromJson ignorava o ID salvo | Recarregar animes/títulos com ID explícito podia quebrar a associação com favoritos/histórico | Preserva ID existente; mantém o identificador derivado para registros legados sem ID |
| Leitura do ano usava o primeiro span, frequentemente DUBLADO/LEGENDADO | Ano zero, ordenação ruim e correspondências de metadados prejudicadas | Lê spans da área de dados do card, sem inferir o ano a partir do título |
| Mesclagem descartava stream_url, stream_headers e backdrop_url | Um item direto podia perder a opção de reprodução ou os cabeçalhos exigidos | Preserva URL e seus cabeçalhos correspondentes, além dos demais campos |
| Ano zero e ano preenchido viravam grupos diferentes, mesmo com o mesmo ID da fonte | Duplicação após corrigir a data | Reconcilia ano desconhecido pelo identificador da mesma fonte; não junta automaticamente remakes de anos conhecidos diferentes |
| Um único progresso ou item de histórico inválido interrompia toda a leitura | Player podia falhar ao inicializar ou o histórico inteiro ficar vazio | Validação por registro e isolamento dos inválidos; leituras aguardam gravações pendentes |
| Retomada não guardava o player/áudio escolhido | Continuar podia pedir nova escolha ou usar outro player sem a posição associada | Salva o rótulo do player e o utiliza na retomada automática; mantém alternativas se a opção não existir mais |
| Busca de animes continuava agendada após trocar Recentes/A–Z/Novidades; respostas antigas alteravam flags | Mudança involuntária de aba, filtros inconsistentes ou resultados antigos | Cancela debounce, verifica a geração de cada consulta e captura a fonte usada; limpa o campo ao escolher letra/fonte |
| Escritas concorrentes de notificações liam/salvavam a mesma lista sem exclusão mútua | Um aviso novo podia sobrescrever outro | Operações de escrita serializadas, validação de acompanhamentos e correspondência pelo ID da fonte |
| Exclusão de download não tratava exceções do Android | Erro sem mensagem ou exceção na tela | Captura falhas, mantém a lista e informa que a ação pode ser repetida; evita Snackbar em tela já descartada |
| Duas ações de assistir podiam aguardar o mesmo carregamento de capítulos antes de marcar resolução ativa | Possibilidade de abrir dois players | Confere novamente a fonte e o estado de resolução depois da espera |

## Múltiplas fontes por título

Ao abrir os detalhes, o app pesquisa alternativas nos catálogos existentes, incluindo explicitamente Mega Filmes/Anime, Animes Online e SuperFlix/Anime para títulos episódicos. A fonte original continua disponível durante a busca. As opções são deduplicadas por provedor e identificador e preservam a escolha atual e os capítulos específicos de cada fonte. Há atualização manual das alternativas.

A correspondência usa IMDb publicado quando disponível; na ausência dele, título normalizado e ano compatível, separando filmes de conteúdo episódico. Anos desconhecidos não vinculam automaticamente remakes ambíguos. O caso Dragon Ball Daima está coberto por regressão: Anime e Mega entram no mesmo detalhe mesmo que um catálogo classifique como série. IDs, tipo e histórico do título escolhido são preservados.

Áudio e resolução são propriedades de cada opção, persistidas no cache/histórico, e só aparecem quando publicados nos dados da fonte. Descrições SEO como “dublado e legendado HD” não comprovam as faixas de um vídeo. A busca cobre as páginas de resultados disponibilizadas pelos provedores; não garante enumerar servidores internos não publicados ou títulos com traduções diferentes sem identidade confirmada.

## Validação

Testes de regressão reproduzem: favorito fora da Home e após recarregar, migração e gravação concorrente, IDs estáveis, qualidade antes da data, preservação de mídia direta, distinção de remakes, progresso corrompido, retomada com rótulo de player, gravação concorrente de avisos, busca de animes fora de ordem/cancelada e erro nativo na exclusão.

A publicação passa pelos testes existentes e novos, análise estática, build release e assinatura permanente. A validação nativa de hash, pacote, versão e certificado do APK foi revisada e preservada.

## Limites e observações

- Favoritos antigos que só possuam ID precisam que os dados do título ainda existam no catálogo local ou voltem a ser encontrados. Não são inventadas fichas para IDs sem informações recuperáveis.
- A retomada por posição vale para o player nativo. Iframes continuam dependendo das capacidades e verificações da fonte.
- A disponibilidade, anúncios, mudanças de domínio e bloqueios de fontes externas não são controlados pelo app. A auditoria não promete que todos os canais ou títulos de terceiros estejam disponíveis.
- O backend de metadados é opcional; dados IMDb/Rotten Tomatoes continuam exigindo correspondência confirmada e acesso à informação publicada. Nenhuma chave privada foi adicionada ao APK.
