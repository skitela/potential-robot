# Natychmiastowy odczyt i odpowiedz do Codexa

To jest prosty kontrakt pracy brygady. Nie trzeba zgadywac, jak czytac i jak odpowiadac.

## Rytm obowiazkowy

1. zsynchronizuj odczyt nowych notatek dla wszystkich brygad albo sprawdz receipt,
2. odczytaj wlasne notatki z trescia,
3. jesli masz task albo jestes targetem, wykonaj review bezpieczenstwa,
4. odpowiedz do Codexa jednym standardowym raportem wyniku.

## Komenda 1 - natychmiastowy sync notatek

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\FORCE_BRIGADE_NOTE_SYNC.ps1
```

To aktualizuje receipts i publikuje raport doreczenia latest note.

## Komenda 2 - odczyt notatek konkretnej brygady

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\READ_ORCHESTRATOR_BRIGADE_NOTES.ps1 -BrigadeId rozwoj_kodu -Limit 10 -ShowContent
```

## Komenda 3 - odpowiedz brygady do Codexa

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\WRITE_BRIGADE_REPLY_TO_CODEX.ps1 `
  -TaskId <task_id> `
  -BrigadeId rozwoj_kodu `
  -Outcome STATUS `
  -Summary "Co zostalo sprawdzone i w jakim jest stanie." `
  -Checked "plik A", "plik B" `
  -Confirmed "fakt 1", "fakt 2" `
  -Blockers "blokada 1" `
  -CodexAction "Jaka decyzja albo merge jest potrzebny od Codexa." `
  -NextAction "Co ta brygada zrobi dalej."
```

## Minimalna forma odpowiedzi

- `Summary`
- `Checked`
- `Confirmed`
- `Blockers`
- `Delegate further work`
- `Codex action`
- `Next action`

Ta forma wraca do Codexa i jest widoczna dla pozostalych brygad tylko do odczytu.

## Zasada routingu

- wszystkie brygady czytaja wszystkie nowe noty,
- odpowiada i wykonuje tylko adresat albo wlasciciel tasku,
- pytania nie ida miedzy brygadami, tylko do Codexa,
- jesli potrzebna jest inna brygada, robi sie `note + task handoff`.

## Gdzie wraca wynik

Raport wyniku wraca do wspolnego inboxu mostu:

`C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox\notes\inbox`

ale domyslnym odbiorca i koordynatorem pozostaje Codex.
