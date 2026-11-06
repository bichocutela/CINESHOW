# Sincronização dos diretórios ao vivo

O workflow `Sync public live directories` atualiza a branch `live-data` a cada 30 minutos. O app usa esses JSONs como reserva quando a fonte direta está indisponível. A correção deste fluxo não exige instalar outro APK.

## Falha investigada

Execução `42145688310`, commit `7ac3162`: o script interrompeu com `ValueError: Empty directory must not replace a valid snapshot`. Uma resposta vazia encerrava o processo antes de concluir as duas categorias.

## Comportamento corrigido

- Canais e agenda são consultados separadamente, com até três tentativas e espera progressiva.
- Uma agenda explicitamente vazia (`success: true`, `data: []`) é válida. Uma lista de canais vazia ou uma resposta cujos registros são todos inválidos não apaga dados verificados.
- Em indisponibilidade ou resposta incompatível, conserva a versão verificada da branch `live-data`; os arquivos embarcados são a última reserva. A data original de verificação é preservada.
- Atualizações parciais preservam os outros arquivos da branch por meio de `base_tree`. Se nenhum conteúdo mudou, não cria outro commit.
- O resumo do Actions e o artefato `sync-status.json` distinguem `updated`, `retained` e `unavailable`. Reserva não é anunciada como consulta atualizada.
- Falhas de autenticação/permissão/publicação no GitHub e ausência de uma reserva válida continuam encerrando com erro. Não há `continue-on-error` para ocultar esses problemas.
- Os testes rodam antes de cada sincronização e também em pull requests que alteram o fluxo. Pull requests não publicam dados.

Fontes externas ainda podem ficar indisponíveis. A proteção trata isso conservando os dados existentes e registrando um aviso, sem prometer a disponibilidade das transmissões.
