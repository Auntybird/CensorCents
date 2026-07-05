# Tiger Wallet 🐯💰

A gamified budgeting app. Log a transaction, and a strict, blunt, traditional
"Tiger Parent" AI (Llama 3 via Groq) tells you exactly what it thinks of your
spending decisions.

**Stack:** Flutter (Dart) + Supabase (Auth/Postgres/Realtime) + Groq API (Llama 3)

## Project structure

```
tiger_wallet/
├── supabase_schema.sql        # Run this in the Supabase SQL editor first
├── .env.example                # Copy to .env and fill in your keys
├── pubspec.yaml
└── lib/
    ├── main.dart                          # App entry point, auth gate
    ├── theme/app_theme.dart               # Dark theme, red/green accents
    ├── models/
    │   ├── user_profile_model.dart
    │   └── transaction_model.dart
    ├── services/
    │   ├── supabase_service.dart          # Auth, profile, transactions, Realtime
    │   ├── groq_service.dart              # Llama 3 "Tiger Parent" persona
    │   └── wallet_controller.dart         # Orchestrates the 5-step workflow
    ├── widgets/
    │   ├── stern_avatar.dart              # Mood-reactive avatar (CustomPaint)
    │   ├── add_transaction_sheet.dart     # Amount + category input form
    │   └── ai_feedback_sheet.dart         # Animated critique bottom sheet
    └── screens/
        ├── login_screen.dart
        └── dashboard_screen.dart
```

## Setup

### 1. Supabase

1. Create a project at https://supabase.com.
2. Open **SQL Editor** → paste the entire contents of `supabase_schema.sql` → **Run**.
   This creates the `users` and `transactions` tables, RLS policies, a
   trigger that auto-provisions a `users` row on signup, and enables Realtime
   on `transactions`.
3. Go to **Project Settings → API** and copy your **Project URL** and **anon public key**.

### 2. Groq

1. Create an account at https://console.groq.com.
2. Go to **API Keys** → create a new key.
3. Note the model name you want (e.g. `llama3-70b-8192` or `llama3-8b-8192`).

### 3. Configure secrets

```bash
cp .env.example .env
```

Edit `.env`:

```
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_ANON_KEY=YOUR_ANON_KEY
GROQ_API_KEY=YOUR_GROQ_KEY
GROQ_MODEL=llama3-70b-8192
```

`.env` is already referenced in `pubspec.yaml` assets and is loaded by
`flutter_dotenv` in `main.dart`. Add `.env` to your `.gitignore` — never commit it.

### 4. Install & run

```bash
flutter pub get
flutter run
```

## How the AI workflow works (per spec)

1. User fills in amount + category in `AddTransactionSheet` and taps Submit.
2. `WalletController.submitTransaction` calls `SupabaseService.insertTransaction`
   — the raw row (no `ai_feedback` yet) is written immediately, so the entry
   shows up in the list right away.
3. The controller recomputes the monthly total (`fetchCurrentMonthTotal`) and
   calls `GroqService.critiqueTransaction`, which POSTs to
   `https://api.groq.com/openai/v1/chat/completions` with the "Tiger Parent"
   system prompt plus the transaction context.
4. The returned critique string is patched back onto the same row via
   `SupabaseService.updateTransactionFeedback` (`UPDATE ... SET ai_feedback = ...`).
5. Because the dashboard is subscribed to `SupabaseService.watchTransactions()`
   (a Supabase Realtime stream), the UPDATE event arrives automatically and
   `DashboardScreen` pops the animated `AiFeedbackSheet` the instant the
   feedback lands — no polling, no manual refresh.

## Customizing the persona

All personality/tone logic lives in `lib/services/groq_service.dart` inside
the `_systemPrompt` constant. To support multiple personas driven by the
`parent_personality` column, branch on `parentPersonality` there and swap in
different system prompt variants (e.g. "Strict", "Skeptical", "Passive-Aggressive").

## Avatar assets

The stern avatar (`lib/widgets/stern_avatar.dart`) currently draws its face
procedurally with `CustomPaint` so the app runs without needing any image
assets. To use real illustrated art instead: drop PNG/SVG files into
`assets/avatars/` (already registered in `pubspec.yaml`), then swap the
`CustomPaint` body in `SternAvatar` for an `Image.asset(...)` call keyed off
`ParentMood` — a commented-out example mapping is already in that file.
