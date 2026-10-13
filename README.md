# CINESHOW

Catálogo Flutter de filmes, séries e novelas com conectores públicos de Xonados,
RTFilmes (Pobreflix) e Tontons (TopFlix).

- Catálogo inicial verificado, cache persistente e atualização ao abrir/puxar a tela.
- Busca DooPlay, agrupamento de fontes e filtros por tipo.
- Favoritos, detalhes, episódios de séries e capítulos/variantes do Xonados.
- Reprodução na fonte original; player nativo separado para mídia autorizada.
- API Python opcional, armazenamento SQLite e eventos de novos títulos.
- Workflow de validação, APK Android e releases com assinatura permanente.
- Consulta manual de novas versões na aba Sobre.

Leia [configuração e limites](docs/INTEGRATION.md). Push com o app fechado requer
backend hospedado e configuração de mensageria; ainda não está ativo.

## Desenvolvimento

Flutter 3.35.7:
```sh
flutter create --platforms=android --org=com.bichocutela --project-name=cineshow .
python scripts/configure_android.py
flutter pub get
flutter analyze
flutter test
```

Backend:
```sh
python -m unittest discover -s tests -v
python -m backend.server
```
