// Studio IA : génère un cursus avec Claude. Réservé aux administrateurs.
// La clé est lue dans le secret ANTHROPIC_API_KEY (jamais dans le navigateur).
// Le code de construction des prompts est copié depuis index.html (même logique, même résultat).
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

// ---- Copié depuis index.html ----
// deno-lint-ignore-file no-explicit-any
const AI_MODEL = 'claude-sonnet-5-5';
const MAX_SOURCE_CHARS = 200000;
const SRC_KIND = { voice: 'Dictée', paste: 'Texte collé', pdf: 'PDF', docx: 'Word', md: 'Markdown', txt: 'Texte' };
const CHECKLIST_PROP = { type: 'array', items: { type: 'string' } };
const PLAN_TOOL = {
  name: 'plan_course',
  description: "Enregistre le plan du cursus d'onboarding.",
  input_schema: { type: 'object', required: ['title', 'description', 'modules'], properties: {
    title: { type: 'string' }, description: { type: 'string' },
    modules: { type: 'array', items: { type: 'object', required: ['title', 'objective', 'est_minutes', 'chapters'], properties: {
      title: { type: 'string' }, objective: { type: 'string' }, est_minutes: { type: 'integer' },
      chapters: { type: 'array', items: { type: 'object', required: ['title', 'lessons'], properties: {
        title: { type: 'string' }, lessons: { type: 'array', items: { type: 'string' }, description: 'Titres des leçons' } } } } } } } } },
};
const MODULE_TOOL = {
  name: 'write_module',
  description: "Enregistre le contenu complet d'un module.",
  input_schema: { type: 'object', required: ['chapters'], properties: {
    chapters: { type: 'array', items: { type: 'object', required: ['title', 'lessons'], properties: {
      title: { type: 'string' },
      lessons: { type: 'array', items: { type: 'object', required: ['title', 'est_minutes', 'content'], properties: {
        title: { type: 'string' }, est_minutes: { type: 'integer' },
        content: { type: 'string', description: 'Contenu de la leçon en Markdown (### sous-titres, listes, **gras**).' },
        checklist: CHECKLIST_PROP } } } } } },
    quiz: { type: 'object', properties: { pass_score: { type: 'integer' }, questions: { type: 'array', items: { type: 'object', required: ['prompt', 'options'], properties: {
      prompt: { type: 'string' }, explanation: { type: 'string' },
      options: { type: 'array', items: { type: 'object', required: ['text', 'correct'], properties: { text: { type: 'string' }, correct: { type: 'boolean' }, feedback: { type: 'string' } } } } } } } } },
    exercise: { type: 'object', properties: { title: { type: 'string' }, instructions: { type: 'string' }, submission_type: { type: 'string', enum: ['file', 'link', 'both'] } } },
  } },
};
const LEVEL_TXT = { debutant: 'nouvel arrivant, sans connaissance préalable', intermediaire: 'collaborateur déjà opérationnel qui approfondit', avance: 'collaborateur expérimenté (perfectionnement)' };
const DURATION_TXT = { auto: 'selon la quantité de contenu', '1h': 'environ 1 heure au total', 'demi-journee': 'environ une demi-journée', '1j': 'environ une journée', '3j': '2 à 3 jours' };
const COURSE_RULES = `Tu es concepteur pédagogique senior chez Hike UP, une agence qui accompagne des entreprises industrielles B2B dans leur prospection commerciale et leur génération de leads. Tu transformes des contenus bruts (transcriptions de dictée, documents internes, notes, procédures) en cursus d'onboarding clairs, structurés et actionnables, en français.

Règles :
- N'invente aucun fait absent des sources (chiffres, noms de clients, outils, procédures). Quand une information utile manque, écris « [À compléter : …] » dans la leçon.
- Réécris l'oral en écrit soigné : supprime hésitations et répétitions, garde le vocabulaire métier et les exemples concrets.
- Un module = une compétence. Chaque leçon fait 150 à 400 mots en Markdown (### pour les sous-titres, listes à puces, **gras** pour les règles importantes), avec un exemple concret tiré des sources quand il existe.
- Checklist : 2 à 4 points clés vérifiables par leçon, à la première personne (« Je sais… »).
- Quiz : 3 à 5 questions par module qui vérifient la compréhension et le bon réflexe en situation, pas la mémorisation mot à mot ; 3 ou 4 options, une seule correcte, un feedback court par option.
- Exercice : une tâche concrète réalisable dans les outils cités par les sources, avec le livrable attendu (fichier ou lien).
- Durées réalistes en minutes.`;
function sourcesBlock(sources) {
  let budget = MAX_SOURCE_CHARS;
  return 'Sources fournies par l\'administrateur :\n\n' + sources.map(s => {
    const t = String(s.text).slice(0, Math.max(0, budget)); budget -= t.length;
    return `<source nom="${String(s.name).replace(/"/g, "'")}" type="${SRC_KIND[s.kind] || s.kind}">\n${t}\n</source>`;
  }).join('\n\n');
}
function paramsText(st, folderNames) {
  return `Paramètres :
- Destinataires : ${folderNames.length ? folderNames.join(', ') : 'collaborateurs Hike UP'}${folderNames.length > 1 ? ' (tronc commun partagé par plusieurs rôles : reste général, sans spécificité d\'un seul rôle)' : ''}
- Niveau : ${LEVEL_TXT[st.level] || st.level}
- Nombre de modules : ${st.modules === 'auto' ? 'à déterminer selon le contenu (2 à 7 en général)' : st.modules}
- Durée cible : ${DURATION_TXT[st.duration] || st.duration}
- Quiz par module : ${st.quiz ? 'oui' : 'non'}
- Exercice pratique par module : ${st.exercises ? 'oui' : 'non'}
- Checklist par leçon : ${st.checklist ? 'oui' : 'non'}
${st.title ? `- Titre imposé : ${st.title}\n` : ''}${st.instructions ? `- Consignes supplémentaires : ${st.instructions}\n` : ''}`;
}
/* Construit la requête Claude pour un appel "outline" ou "module" */
function buildClaudeRequest(kind, p) {
  const system = [{ type: 'text', text: COURSE_RULES }, { type: 'text', text: sourcesBlock(p.sources), cache_control: { type: 'ephemeral' } }];
  if (kind === 'outline') {
    return { system, max_tokens: 4000, tool: PLAN_TOOL,
      user: `${paramsText(p.settings, p.folderNames)}\nÉtablis le plan du cursus à partir des sources : titre, description (1 à 2 phrases), modules avec objectif et durée, chapitres et titres des leçons. Le plan doit couvrir tout le contenu utile des sources, dans un ordre progressif. Appelle l'outil plan_course.` };
  }
  const m = p.outline.modules[p.index];
  return { system, max_tokens: 8000, tool: MODULE_TOOL,
    user: `${paramsText(p.settings, p.folderNames)}\nPlan complet du cursus « ${p.outline.title} » :\n${p.outline.modules.map((x, i) => `${i + 1}. ${x.title} : ${x.chapters.map(c => c.title).join(' ; ')}`).join('\n')}\n\nRédige maintenant en entier le module ${p.index + 1} « ${m.title} » (objectif : ${m.objective}).\nChapitres et leçons prévus :\n${m.chapters.map(c => `- ${c.title} : ${(c.lessons || []).join(' / ')}`).join('\n')}\n\nNe traite que ce module (les autres sont rédigés séparément, évite les doublons). ${p.settings.quiz ? 'Inclus le quiz.' : 'N\'inclus pas de quiz.'} ${p.settings.exercises ? 'Inclus l\'exercice pratique.' : 'N\'inclus pas d\'exercice.'} Appelle l'outil write_module.` };
}
// ---- Fin de la copie ----

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: { user } } = await sb.auth.getUser();
    if (!user) return json({ error: "Non connecté." }, 401);
    const { data: isAdmin } = await sb.rpc("has_role", { r: "admin" });
    if (!isAdmin) return json({ error: "Réservé aux administrateurs." }, 403);

    const key = Deno.env.get("ANTHROPIC_API_KEY");
    if (!key) return json({ error: "Clé Claude absente : ajoutez le secret ANTHROPIC_API_KEY dans Supabase." }, 500);

    const { kind, ...payload } = await req.json();
    if (kind !== "outline" && kind !== "module") return json({ error: "Requête invalide." }, 400);
    const r: any = (buildClaudeRequest as any)(kind, payload);
    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "content-type": "application/json", "x-api-key": key, "anthropic-version": "2023-06-01" },
      body: JSON.stringify({ model: AI_MODEL, max_tokens: r.max_tokens, system: r.system, messages: [{ role: "user", content: r.user }], tools: [r.tool], tool_choice: { type: "tool", name: r.tool.name } }),
    });
    const out = await res.json().catch(() => ({}));
    if (!res.ok) return json({ error: out?.error?.message || `Erreur Claude ${res.status}` });
    if (out.stop_reason === "max_tokens") return json({ error: "Réponse tronquée : réduisez le nombre de modules ou la taille des sources." });
    const block = (out.content || []).find((b: any) => b.type === "tool_use");
    if (!block) return json({ error: "La réponse de l'IA ne contient pas le résultat attendu." });
    return json({ result: block.input });
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500);
  }
});
