# 💿 Subst Manager

GUI per gestire il comando `subst` di Windows: crea, visualizza e rimuovi dischi virtuali da cartelle, con persistenza all'avvio.

## ✨ Feature

- ✅ **Aggiungi associazioni**: mappa una cartella a una lettera di unità (es. `S:` => `C:\Documenti`)
- ✅ **Visualizza associazioni**: vedi tutte le associazioni SUBST esistenti
- ✅ **Elimina associazioni**: rimuovi un disco virtuale con un click
- ✅ **Lettere disponibili**: mostra quali lettere sono libere
- ✅ **Mappature di rete**: mostra le lettere già usate da share di rete
- ✅ **Persistenza**: crea uno script `.bat` nella cartella Startup per ripristinare le associazioni al riavvio
- ✅ **Apri cartella**: doppio click su un'associazione per aprire la cartella
- ✅ **Auto-elevazione admin**: chiede i privilegi UAC all'avvio
- ✅ **Log su file**: `SubstManager_*.log`

## 📋 Requisiti

- **Windows 10 / 11**
- **PowerShell 7+** (scarica da https://aka.ms/powershell)
- **Privilegi di amministratore** (per `subst`)

## 🚀 Quick start

```powershell
git clone https://github.com/fabrytoolbox/Subst-Manager.git
cd Subst-Manager
Unblock-File .\Subst-Manager.ps1
.\Subst-Manager.ps1

Oppure doppio click su avvia.bat.

🎯 Casi d'uso
Mappare una cartella a una lettera (es. S: per i tuoi script)

Creare dischi virtuali per accedere rapidamente a cartelle profonde

Rendere persistenti le associazioni dopo un riavvio

Pulire associazioni SUBST vecchie o inutilizzate

💡 Suggerimento
Usa le lettere O-S per SUBST e T-Z per le mappature di rete. È una convenzione che evita conflitti.

🐛 Problemi comuni
"Accesso negato"
Il tool richiede privilegi di amministratore. Accetta il prompt UAC quando appare.

"La lettera è già in uso"
Scegli una lettera diversa. La GUI mostra quelle disponibili.

"La persistenza non funziona"
Verifica che il file SubstPersistence.bat sia nella cartella Startup (%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup).

📜 Licenza
MIT (vedi LICENSE).

🙏 Crediti
Fabry Toolbox

PowerShell 7 + WinForms

Comando subst di Windows