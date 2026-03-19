# 144 QDM Secret Vault V1

## Cel
- przechowywac numer licencji `QuantDataManager` poza zwyklymi plikami tekstowymi
- umozliwic automatyczne podawanie licencji do `QDM`
- nie mieszac kodu licencji z repozytorium

## Co zostalo zrobione
### 1. Lokalny vault sekretow
Skonfigurowano lokalny vault PowerShell:
- `MicroBotVault`

Technicznie:
- modul `Microsoft.PowerShell.SecretManagement`
- modul `Microsoft.PowerShell.SecretStore`

Vault dziala lokalnie dla obecnego uzytkownika Windows.

### 2. Zapis kodu licencji do vaulta
Dodano skrypt:
- [STORE_QDM_LICENSE_SECRET.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\STORE_QDM_LICENSE_SECRET.ps1)

Mozna go uruchomic:
- z parametrem `-Code`
- albo bez parametru, wtedy poprosi o kod lokalnie

### 3. Automatyczne zastosowanie licencji do QDM
Dodano skrypt:
- [APPLY_QDM_LICENSE_FROM_SECRET.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\APPLY_QDM_LICENSE_FROM_SECRET.ps1)

Skrypt:
- pobiera kod z `MicroBotVault`
- przekazuje go do:
  - [QDM_LICENSE.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\QDM_LICENSE.ps1)

### 4. Jeden krok: zapisz i zastosuj
Dodano skrypt:
- [STORE_AND_APPLY_QDM_LICENSE.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\STORE_AND_APPLY_QDM_LICENSE.ps1)

Ten skrypt:
- prosi o kod licencji
- zapisuje go do vaulta
- od razu probuje zastosowac go w `QDM`

## Bezpieczny workflow
1. zapis kodu do vaulta
2. zastosowanie licencji z vaulta
3. uruchomienie `QDM`

## Przyklady
Zapis z promptem:
- `powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\RUN\STORE_QDM_LICENSE_SECRET.ps1`

Zapis z parametrem:
- `powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\RUN\STORE_QDM_LICENSE_SECRET.ps1 -Code TWOJ_KOD`

Zastosowanie licencji:
- `powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\RUN\APPLY_QDM_LICENSE_FROM_SECRET.ps1`

Wszystko jednym krokiem:
- `powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\RUN\STORE_AND_APPLY_QDM_LICENSE.ps1`

## Granica
Kod licencji:
- nie jest zapisany w repo
- nie jest wpisany na sztywno do skryptow
- siedzi tylko w lokalnym vault PowerShell
