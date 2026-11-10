# Farma&Cia Flutter (Android, iOS e Web)

O app usa a API ASP.NET do projeto `Farmacia_site`; ele não acessa o SQL Server diretamente. No Android e iOS, o catálogo sincronizado fica em SQLite no aparelho. No Web, o cache offline usa o armazenamento local do navegador.

## Versão publicada (Azure + GitHub Pages)

- App Flutter (código): https://github.com/Audrey8011/farmaecia-flutter
- API ASP.NET (Azure): https://farmaecia-api-audrey-2026.azurewebsites.net/api
- Loja MVC em execução (Azure): https://farmaecia-mvc-audrey-2026.azurewebsites.net/
- Vitrine estática (GitHub Pages): https://audrey8011.github.io/farmaecia/

O banco Azure SQL (`FarmaECiaDb`, oferta gratuita) é compartilhado entre o MVC e a API. No aparelho, o SQLite continua sendo apenas o cache offline.

Para gerar um APK apontando para a API pública:

```powershell
flutter build apk --debug --dart-define=API_BASE_URL=https://farmaecia-api-audrey-2026.azurewebsites.net/api
```

## Executar localmente

1. Inicie a API em `Farmacia_site/Farmacia_site` com `dotnet run`.
2. Execute `flutter pub get` nesta pasta.
3. Inicie no navegador com `flutter run -d chrome` ou em um emulador Android com `flutter run -d <dispositivo>`.

### Android SDK local

O SDK Android e o JDK 17 ficam em `.android-sdk/` neste projeto e são ignorados pelo Git por serem ferramentas grandes. Para apontar o Flutter para eles novamente:

```powershell
flutter config --android-sdk "$PWD\.android-sdk"
flutter config --jdk-dir "$PWD\.android-sdk\jdk-17"
flutter doctor --android-licenses
```

O SDK instalado inclui platform-tools, Android API 36, Build Tools 36.0.0 e NDK 28.2.13676358.

No Web/iOS, o endereço padrão da API é `http://localhost:5178/api`; no emulador Android é `http://10.0.2.2:5178/api`. Para outro endereço (por exemplo, um celular físico na rede local), configure:

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=https://localhost:7097/api
```

O catálogo salvo é exibido imediatamente quando o app abre sem internet. Quando a conexão volta, o app tenta sincronizar automaticamente; também verifica novamente ao retornar ao primeiro plano e repete a tentativa após falhas temporárias.

Pedidos ainda precisam de conexão para serem enviados e confirmados pelo servidor; eles não são colocados em fila offline.

No deploy, use uma URL HTTPS pública para `API_BASE_URL` e configure CORS no backend para a origem publicada.

Para produção, configure no ambiente do ASP.NET:

- `ConnectionStrings__FarmaECiaDb`: conexão do SQL Server;
- `Jwt__Key`: chave aleatória secreta de pelo menos 32 bytes;
- `Jwt__Issuer` e `Jwt__Audience`: valores do emissor e público do token;
- `Cors__AllowedOrigins__0`: origem HTTPS do app Flutter publicado.
