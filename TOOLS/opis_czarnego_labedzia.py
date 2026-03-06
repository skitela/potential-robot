#!/usr/bin/env python3
"""
OANDA_MT5_SYSTEM: opis mechanizmu "Czarny Labedz".

Plik jest opisowy (dla operatora i zespolu) i streszcza to, jak dziala
detekcja oraz reakcja runtime, bez ingerencji w hot-path.

Zrodla implementacyjne:
- BIN/black_swan_guard.py
- BIN/safetybot.py
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from textwrap import dedent
import argparse


@dataclass(frozen=True)
class BlackSwanContract:
    threshold: float = 3.0
    precaution_fraction: float = 0.8
    ewma_alpha: float = 0.02
    stress_weight_volatility: float = 0.6
    stress_weight_spread: float = 0.4
    stress_clip_min: float = 0.0
    stress_clip_max: float = 10.0


def build_description(contract: BlackSwanContract) -> str:
    precaution_level = contract.threshold * contract.precaution_fraction
    return dedent(
        f"""
        OANDA_MT5_SYSTEM - ZASADA DZIALANIA "CZARNY LABEDZ"
        ===================================================

        1) Cel mechanizmu
        - Wykryc rzadkie, nienormalne warunki rynku (skok zmiennosci i/lub kosztu),
          zanim system wejdzie w zbyt ryzykowne transakcje.
        - Ograniczyc straty przez szybkie przejscie do trybu ochronnego.

        2) Jak liczony jest poziom stresu rynku
        - Guard liczy globalny indeks stresu na bazie:
          - odchylenia zmiennosci (waga {contract.stress_weight_volatility:.2f}),
          - odchylenia spreadu (waga {contract.stress_weight_spread:.2f}).
        - Wynik jest obcinany do zakresu [{contract.stress_clip_min:.1f}, {contract.stress_clip_max:.1f}].
        - Tlo referencyjne jest aktualizowane przez EWMA (alpha={contract.ewma_alpha:.2f}).
        - Gdy wykryty jest "czarny labedz", EWMA jest zamrazane
          (zeby anomalia nie "rozmyla" progu).

        3) Progi decyzyjne
        - Tryb ostrzegawczy (prewencja): indeks >= {precaution_level:.2f}
          (czyli threshold * precaution_fraction).
        - Tryb "czarny labedz": indeks >= {contract.threshold:.2f}.

        4) Co robi SafetyBot
        - Jezeli jest za malo danych o zmiennosci:
          - nie stwierdza "czarnego labedzia",
          - zwraca powod: INSUFFICIENT_VOL_DATA.
        - Jezeli wykryty jest "czarny labedz":
          - przechodzi w tryb ECO,
          - blokuje nowe wejscia (VETO_NEW_ENTRIES),
          - opcjonalnie uruchamia kill-switch (zalezne od konfiguracji),
            ktory zamyka pozycje przez force_flat_all.
        - Jezeli jest tylko prewencja:
          - przechodzi w ECO,
          - podnosi warning STRESS_PRECAUTION.

        5) Dlaczego to chroni system i kapital
        - System nie "goni" rynku w chwili skokowej destabilizacji.
        - Ogranicza przypadki wejsc w momentach ekstremalnego spreadu/latencji.
        - Daje kontrolowany powrot do normalnego trybu po ustaniu stresu.

        6) Czego ten mechanizm NIE robi
        - Nie gwarantuje zysku.
        - Nie zastapi risk managera.
        - Nie zastapi kontroli operatora na poziomie deploymentu.
        """
    ).strip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generuje opis mechanizmu 'Czarny Labedz' dla OANDA_MT5_SYSTEM."
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Opcjonalna sciezka do zapisu opisu .txt",
    )
    args = parser.parse_args()

    text = build_description(BlackSwanContract())

    if args.output:
        out = Path(args.output)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text, encoding="utf-8")
        print(f"Zapisano opis: {out}")
    else:
        print(text)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
