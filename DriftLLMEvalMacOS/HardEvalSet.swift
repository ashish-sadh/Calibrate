import Foundation

// MARK: - Types

enum EvalCategory: String, CaseIterable {
    case foodRouting, regression, multiTurn, supplement, navigation, contextSwitch, quickReplyPills
}

struct ResponseRubric {
    let mustContain: [String]     // response must include at least one of these (OR logic)
    let mustNotContain: [String]  // response must not include any of these
    let maxWords: Int?

    static let any = ResponseRubric(mustContain: [], mustNotContain: [], maxWords: nil)
    static func contains(_ words: String...) -> ResponseRubric {
        ResponseRubric(mustContain: words, mustNotContain: [], maxWords: nil)
    }
    static func notContains(_ words: String...) -> ResponseRubric {
        ResponseRubric(mustContain: [], mustNotContain: words, maxWords: nil)
    }
    static func containsNot(must: [String], not: [String], maxWords: Int? = nil) -> ResponseRubric {
        ResponseRubric(mustContain: must, mustNotContain: not, maxWords: maxWords)
    }
}

struct HardCase {
    let input: String
    let history: String?
    let expectedTool: String          // "chat" for text-only responses
    let expectedParamHints: [String: String]  // param key → expected substring (case-insensitive)
    let responseRubric: ResponseRubric
    let category: EvalCategory
    let description: String
    let isTrainSet: Bool              // true = train (70), false = held-out (30)
}

// MARK: - Eval Set

enum HardEvalSet {

    static let all: [HardCase] = foodRouting + regression + multiTurn + supplement + navigation + contextSwitch + quickReplyPills

    // MARK: - Food Routing (implicit logging, no "log" keyword) — 30 cases

    static let foodRouting: [HardCase] = [
        HardCase(input: "Dal chawal again 🙄", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "dal"],
                 responseRubric: .contains("dal", "logged"), category: .foodRouting,
                 description: "Indian food with emoji, no log keyword", isTrainSet: true),

        HardCase(input: "Just wrapped up breakfast, had idli sambar", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "idli"],
                 responseRubric: .contains("idli", "logged"), category: .foodRouting,
                 description: "Implicit past-tense logging with Indian food", isTrainSet: true),

        HardCase(input: "Post-workout shake done", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "shake"],
                 responseRubric: .containsNot(must: ["logged", "shake"], not: ["supplement", "mark"]),
                 category: .foodRouting, description: "Shake is food not supplement", isTrainSet: true),

        HardCase(input: "Khichdi night 🍲", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "khichdi"],
                 responseRubric: .contains("khichdi", "logged"), category: .foodRouting,
                 description: "Single Indian food word + emoji", isTrainSet: true),

        HardCase(input: "Demolished a dosa at the canteen", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "dosa"],
                 responseRubric: .contains("dosa", "logged"), category: .foodRouting,
                 description: "Slang verb 'demolished' = ate", isTrainSet: true),

        HardCase(input: "Uttapam x2 with coconut chutney 👌", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "uttapam"],
                 responseRubric: .contains("uttapam", "logged"), category: .foodRouting,
                 description: "Quantity via 'x2' format", isTrainSet: true),

        HardCase(input: "Snackd on murmura while watching tv", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "murmura"],
                 responseRubric: .contains("murmura", "logged"), category: .foodRouting,
                 description: "Typo in verb + Indian snack", isTrainSet: true),

        HardCase(input: "Breakfast: poached eggs on toast", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "egg"],
                 responseRubric: .contains("egg", "logged"), category: .foodRouting,
                 description: "Colon-separated meal format", isTrainSet: true),

        HardCase(input: "a cup of dal for lunch", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "dal"],
                 responseRubric: .containsNot(must: ["logged"], not: ["cup of dal"]),
                 category: .foodRouting, description: "Amount-first format, name must not include unit", isTrainSet: true),

        HardCase(input: "Just had my morning oats", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "oat"],
                 responseRubric: .contains("oat", "logged"), category: .foodRouting,
                 description: "Time-of-day context + past tense", isTrainSet: true),

        HardCase(input: "Paneer tikka for dinner tonight", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "paneer"],
                 responseRubric: .contains("paneer", "logged"), category: .foodRouting,
                 description: "Multi-word Indian food", isTrainSet: true),

        HardCase(input: "Gobbled up some rajma rice", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "rajma"],
                 responseRubric: .contains("rajma", "logged"), category: .foodRouting,
                 description: "Informal verb 'gobbled'", isTrainSet: true),

        HardCase(input: "Chole bhature for lunch 😋", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "chole"],
                 responseRubric: .contains("chole", "logged"), category: .foodRouting,
                 description: "Indian street food + emoji", isTrainSet: true),

        HardCase(input: "Had a protein bar after gym", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "protein bar"],
                 responseRubric: .contains("logged"), category: .foodRouting,
                 description: "Protein bar = food not supplement", isTrainSet: true),

        HardCase(input: "Ate some almonds and dates as snack", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "almond"],
                 responseRubric: .contains("logged"), category: .foodRouting,
                 description: "Multiple foods in snack context", isTrainSet: true),

        HardCase(input: "Maggi noodles at midnight 🌙", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "maggi"],
                 responseRubric: .contains("maggi", "logged"), category: .foodRouting,
                 description: "Brand name as food", isTrainSet: true),

        HardCase(input: "Just finished lunch — butter chicken with 2 rotis", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "butter chicken"],
                 responseRubric: .contains("logged"), category: .foodRouting,
                 description: "Em dash + quantity", isTrainSet: true),

        HardCase(input: "Smoothie done ✓", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "smoothie"],
                 responseRubric: .contains("logged"), category: .foodRouting,
                 description: "Checkmark emoji as confirmation", isTrainSet: true),

        HardCase(input: "Lunch was aloo paratha with dahi", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "aloo paratha"],
                 responseRubric: .contains("logged"), category: .foodRouting,
                 description: "Past tense 'was' pattern", isTrainSet: true),

        HardCase(input: "Finished my bowl of poha", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "poha"],
                 responseRubric: .contains("poha", "logged"), category: .foodRouting,
                 description: "Container word 'bowl of'", isTrainSet: true),

        // Held-out cases
        HardCase(input: "Pav bhaji for dinner 🔥", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "pav bhaji"],
                 responseRubric: .contains("logged"), category: .foodRouting,
                 description: "Indian street food + fire emoji", isTrainSet: false),

        HardCase(input: "Downed a glass of lassi", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "lassi"],
                 responseRubric: .contains("logged"), category: .foodRouting,
                 description: "'Downed' = consumed liquid", isTrainSet: false),

        HardCase(input: "Grabbed a samosa from the pantry", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "samosa"],
                 responseRubric: .contains("logged"), category: .foodRouting,
                 description: "'Grabbed' = ate", isTrainSet: false),

        HardCase(input: "Dinner: lamb biryani + raita", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "biryani"],
                 responseRubric: .contains("logged"), category: .foodRouting,
                 description: "Colon format with plus separator", isTrainSet: false),

        HardCase(input: "Sneaked in some peanut butter on toast 🤫", history: nil,
                 expectedTool: "log_food", expectedParamHints: ["name": "peanut butter"],
                 responseRubric: .contains("logged"), category: .foodRouting,
                 description: "Colloquial 'sneaked in' = ate", isTrainSet: false),
    ]

    // MARK: - Regression (must NOT log_food) — 25 cases

    static let regression: [HardCase] = [
        HardCase(input: "Is biryani healthy?", history: nil,
                 expectedTool: "food_info",
                 expectedParamHints: [:],
                 responseRubric: .containsNot(must: [], not: ["logged"]),
                 category: .regression, description: "Question about food → food_info not log", isTrainSet: true),

        HardCase(input: "I love eating rajma chawal", history: nil,
                 expectedTool: "chat",
                 expectedParamHints: [:],
                 responseRubric: .containsNot(must: [], not: ["logged"]),
                 category: .regression, description: "Sentiment statement, not a log", isTrainSet: true),

        HardCase(input: "I plan to have idli tomorrow morning", history: nil,
                 expectedTool: "chat",
                 expectedParamHints: [:],
                 responseRubric: .containsNot(must: [], not: ["logged"]),
                 category: .regression, description: "Future intent, not past consumption", isTrainSet: true),

        HardCase(input: "My mom made khichdi but I wasn't hungry", history: nil,
                 expectedTool: "chat",
                 expectedParamHints: [:],
                 responseRubric: .containsNot(must: [], not: ["logged"]),
                 category: .regression, description: "Food mentioned but not eaten", isTrainSet: true),

        HardCase(input: "How many calories in one dosa?", history: nil,
                 expectedTool: "food_info",
                 expectedParamHints: [:],
                 responseRubric: .contains("cal"),
                 category: .regression, description: "Calorie estimation → food_info", isTrainSet: true),

        HardCase(input: "Thinking of going keto — any thoughts?", history: nil,
                 expectedTool: "chat",
                 expectedParamHints: [:],
                 responseRubric: .containsNot(must: [], not: ["logged"]),
                 category: .regression, description: "Diet advice question", isTrainSet: true),

        HardCase(input: "What should I have for dinner tonight?", history: nil,
                 expectedTool: "chat",
                 expectedParamHints: [:],
                 responseRubric: .containsNot(must: [], not: ["logged"]),
                 category: .regression, description: "Future meal suggestion request", isTrainSet: true),

        HardCase(input: "I smell biryani from the kitchen", history: nil,
                 expectedTool: "chat",
                 expectedParamHints: [:],
                 responseRubric: .containsNot(must: [], not: ["logged"]),
                 category: .regression, description: "Sensory observation, not consumption", isTrainSet: true),

        HardCase(input: "Dal is my comfort food", history: nil,
                 expectedTool: "chat",
                 expectedParamHints: [:],
                 responseRubric: .containsNot(must: [], not: ["logged"]),
                 category: .regression, description: "Preference statement, not a log", isTrainSet: true),

        HardCase(input: "I'm thinking of having samosa for snack", history: nil,
                 expectedTool: "chat",
                 expectedParamHints: [:],
                 responseRubric: .containsNot(must: [], not: ["logged"]),
                 category: .regression, description: "Future/uncertain intent", isTrainSet: true),

        HardCase(input: "How many calories in a plate of chole?", history: nil,
                 expectedTool: "food_info",
                 expectedParamHints: [:],
                 responseRubric: .contains("cal"),
                 category: .regression, description: "Calories in question for Indian food", isTrainSet: true),

        HardCase(input: "Biryani makes me so happy", history: nil,
                 expectedTool: "chat",
                 expectedParamHints: [:],
                 responseRubric: .containsNot(must: [], not: ["logged"]),
                 category: .regression, description: "Emotional statement about food", isTrainSet: true),

        HardCase(input: "I was going to log lunch but forgot", history: nil,
                 expectedTool: "chat",
                 expectedParamHints: [:],
                 responseRubric: .containsNot(must: [], not: ["logged"]),
                 category: .regression, description: "Past intended action that didn't happen", isTrainSet: true),

        HardCase(input: "Is paneer high in protein?", history: nil,
                 expectedTool: "food_info",
                 expectedParamHints: [:],
                 responseRubric: .contains("protein"),
                 category: .regression, description: "Nutrient question about food", isTrainSet: true),

        HardCase(input: "I couldn't finish my dal today", history: nil,
                 expectedTool: "chat",
                 expectedParamHints: [:],
                 responseRubric: .containsNot(must: [], not: ["logged"]),
                 category: .regression, description: "Incomplete consumption, not a full log", isTrainSet: true),

        HardCase(input: "Skipped lunch today, not hungry", history: nil,
                 expectedTool: "chat",
                 expectedParamHints: [:],
                 responseRubric: .containsNot(must: [], not: ["logged"]),
                 category: .regression, description: "Skipped meal = no food to log", isTrainSet: true),

        HardCase(input: "I gave my roti to the dog 😂", history: nil,
                 expectedTool: "chat",
                 expectedParamHints: [:],
                 responseRubric: .containsNot(must: [], not: ["logged"]),
                 category: .regression, description: "Food given away, not eaten", isTrainSet: true),

        HardCase(input: "What's healthier — roti or rice?", history: nil,
                 expectedTool: "food_info",
                 expectedParamHints: [:],
                 responseRubric: .containsNot(must: [], not: ["logged"]),
                 category: .regression, description: "Comparison question", isTrainSet: true),

        HardCase(input: "My wife cooked rajma today", history: nil,
                 expectedTool: "chat",
                 expectedParamHints: [:],
                 responseRubric: .containsNot(must: [], not: ["logged"]),
                 category: .regression, description: "Someone else cooked it, no signal of eating", isTrainSet: true),

        HardCase(input: "Ordered pizza but it hasn't arrived yet", history: nil,
                 expectedTool: "chat",
                 expectedParamHints: [:],
                 responseRubric: .containsNot(must: [], not: ["logged"]),
                 category: .regression, description: "Food ordered but not yet consumed", isTrainSet: true),

        // Held-out
        HardCase(input: "Does eating late affect weight loss?", history: nil,
                 expectedTool: "chat",
                 expectedParamHints: [:],
                 responseRubric: .containsNot(must: [], not: ["logged"]),
                 category: .regression, description: "General health question, not a log", isTrainSet: false),

        HardCase(input: "I'm craving idli right now", history: nil,
                 expectedTool: "chat",
                 expectedParamHints: [:],
                 responseRubric: .containsNot(must: [], not: ["logged"]),
                 category: .regression, description: "Craving = future intent, not current consumption", isTrainSet: false),

        HardCase(input: "How much protein is in eggs?", history: nil,
                 expectedTool: "food_info",
                 expectedParamHints: [:],
                 responseRubric: .contains("protein"),
                 category: .regression, description: "Nutrient lookup, not log", isTrainSet: false),

        HardCase(input: "I used to eat biryani every week", history: nil,
                 expectedTool: "chat",
                 expectedParamHints: [:],
                 responseRubric: .containsNot(must: [], not: ["logged"]),
                 category: .regression, description: "Past habitual statement, not recent consumption", isTrainSet: false),

        HardCase(input: "Should I avoid carbs for dinner?", history: nil,
                 expectedTool: "chat",
                 expectedParamHints: [:],
                 responseRubric: .containsNot(must: [], not: ["logged"]),
                 category: .regression, description: "Diet advice question about future meal", isTrainSet: false),
    ]

    // MARK: - Multi-Turn — 15 cases

    static let multiTurn: [HardCase] = [
        HardCase(input: "rice and dal", history: "Assistant: What did you have for lunch?",
                 expectedTool: "log_food", expectedParamHints: ["name": "rice"],
                 responseRubric: .contains("logged"), category: .multiTurn,
                 description: "Answer to 'what did you have' → log_food", isTrainSet: true),

        HardCase(input: "about 300 grams", history: "Assistant: How much chicken did you have?",
                 expectedTool: "log_food", expectedParamHints: ["name": "chicken"],
                 responseRubric: .contains("logged"), category: .multiTurn,
                 description: "Quantity answer to food quantity question", isTrainSet: true),

        HardCase(input: "what about last week", history: "User: how did I sleep\nAssistant: Last night: 7h 20m. Deep sleep 1h 45m. Score 84/100.",
                 expectedTool: "sleep_recovery", expectedParamHints: ["period": "week"],
                 responseRubric: .contains("sleep", "week"), category: .multiTurn,
                 description: "Time continuation in sleep context", isTrainSet: true),

        HardCase(input: "and protein?", history: "User: how am I doing\nAssistant: 930 cal remaining today. You've had 1070/2000 cal.",
                 expectedTool: "food_info", expectedParamHints: [:],
                 responseRubric: .contains("protein"), category: .multiTurn,
                 description: "Topic continuation — protein after food summary", isTrainSet: true),

        HardCase(input: "also add toast", history: "User: log 2 eggs for breakfast\nAssistant: Logged 2 eggs.",
                 expectedTool: "log_food", expectedParamHints: ["name": "toast"],
                 responseRubric: .contains("logged"), category: .multiTurn,
                 description: "Add more to same meal", isTrainSet: true),

        HardCase(input: "make it 3 actually", history: "User: log 2 eggs\nAssistant: Logged 2 eggs.",
                 expectedTool: "log_food", expectedParamHints: ["name": "egg"],
                 responseRubric: .contains("logged"), category: .multiTurn,
                 description: "Correction to previous quantity", isTrainSet: true),

        HardCase(input: "same thing", history: "User: log dal rice for lunch yesterday\nAssistant: Got it — dal and rice logged.",
                 expectedTool: "log_food", expectedParamHints: ["name": "dal"],
                 responseRubric: .contains("logged"), category: .multiTurn,
                 description: "'Same thing' refers to previous food", isTrainSet: true),

        HardCase(input: "and for dinner?", history: "User: what did I have for lunch\nAssistant: Lunch: dal rice 620 cal.",
                 expectedTool: "food_info", expectedParamHints: [:],
                 responseRubric: .contains("dinner"), category: .multiTurn,
                 description: "Meal time continuation", isTrainSet: true),

        HardCase(input: "actually make that 200g", history: "User: I had chicken\nAssistant: How much chicken did you have?",
                 expectedTool: "log_food", expectedParamHints: ["name": "chicken"],
                 responseRubric: .contains("logged"), category: .multiTurn,
                 description: "Direct quantity answer with 'actually'", isTrainSet: true),

        HardCase(input: "yes log it", history: "User: I had biryani\nAssistant: Want me to log biryani?",
                 expectedTool: "log_food", expectedParamHints: ["name": "biryani"],
                 responseRubric: .contains("logged"), category: .multiTurn,
                 description: "Confirmation after clarification", isTrainSet: true),

        HardCase(input: "no skip it", history: "User: I had biryani\nAssistant: Want me to log biryani?",
                 expectedTool: "chat", expectedParamHints: [:],
                 responseRubric: .containsNot(must: [], not: ["logged"]),
                 category: .multiTurn, description: "Denial after clarification → don't log", isTrainSet: true),

        // Held-out
        HardCase(input: "idli sambar", history: "Assistant: What did you have for breakfast?",
                 expectedTool: "log_food", expectedParamHints: ["name": "idli"],
                 responseRubric: .contains("logged"), category: .multiTurn,
                 description: "Indian food answer to breakfast question", isTrainSet: false),

        HardCase(input: "and yesterday's?", history: "User: weight trend\nAssistant: Weight trend: 78.2kg today, down 0.3kg/week.",
                 expectedTool: "weight_info", expectedParamHints: [:],
                 responseRubric: .contains("kg", "weight"), category: .multiTurn,
                 description: "Time shift in weight context", isTrainSet: false),

        HardCase(input: "what about carbs?", history: "User: how's my protein\nAssistant: Today's protein: 68g of 150g goal.",
                 expectedTool: "food_info", expectedParamHints: [:],
                 responseRubric: .contains("carb"), category: .multiTurn,
                 description: "Nutrient topic switch within food domain", isTrainSet: false),

        HardCase(input: "how about this week?", history: "User: how did I sleep last night\nAssistant: Last night: 7h 20m. Score: 84/100.",
                 expectedTool: "sleep_recovery", expectedParamHints: ["period": "week"],
                 responseRubric: .contains("week", "sleep"), category: .multiTurn,
                 description: "Weekly sleep continuation", isTrainSet: false),
    ]

    // MARK: - Supplement — 10 cases

    static let supplement: [HardCase] = [
        HardCase(input: "Creatine done", history: nil,
                 expectedTool: "mark_supplement", expectedParamHints: ["name": "creatine"],
                 responseRubric: .contains("creatine"), category: .supplement,
                 description: "Informal completion marker for supplement", isTrainSet: true),

        HardCase(input: "Forgot to take magnesium", history: nil,
                 expectedTool: "chat", expectedParamHints: [:],
                 responseRubric: .containsNot(must: [], not: ["marked", "logged"]),
                 category: .supplement, description: "Did NOT take — not a mark", isTrainSet: true),

        HardCase(input: "Just popped my evening vitamins", history: nil,
                 expectedTool: "mark_supplement", expectedParamHints: ["name": "vitamin"],
                 responseRubric: .contains("vitamin", "marked"), category: .supplement,
                 description: "'Popped' = took supplement", isTrainSet: true),

        HardCase(input: "Haven't taken my vitamin D yet", history: nil,
                 expectedTool: "supplements", expectedParamHints: [:],
                 responseRubric: .contains("vitamin"), category: .supplement,
                 description: "Status query — not yet taken", isTrainSet: true),

        HardCase(input: "Did I take omega 3 today?", history: nil,
                 expectedTool: "supplements", expectedParamHints: [:],
                 responseRubric: .contains("omega", "fish oil"), category: .supplement,
                 description: "Status check question", isTrainSet: true),

        HardCase(input: "Fish oil down the hatch 🐟", history: nil,
                 expectedTool: "mark_supplement", expectedParamHints: ["name": "fish oil"],
                 responseRubric: .contains("fish oil", "marked"), category: .supplement,
                 description: "Informal phrase + emoji for supplement intake", isTrainSet: true),

        HardCase(input: "Took my morning stack", history: nil,
                 expectedTool: "mark_supplement", expectedParamHints: [:],
                 responseRubric: .contains("marked"), category: .supplement,
                 description: "'Stack' = multiple supplements", isTrainSet: true),

        // Held-out
        HardCase(input: "Zinc and magnesium done for tonight", history: nil,
                 expectedTool: "mark_supplement", expectedParamHints: ["name": "zinc"],
                 responseRubric: .contains("marked"), category: .supplement,
                 description: "Multiple supplements marked at once", isTrainSet: false),

        HardCase(input: "Haven't done supplements yet today", history: nil,
                 expectedTool: "supplements", expectedParamHints: [:],
                 responseRubric: .any, category: .supplement,
                 description: "General supplement status query", isTrainSet: false),

        HardCase(input: "Skipped creatine today", history: nil,
                 expectedTool: "chat", expectedParamHints: [:],
                 responseRubric: .containsNot(must: [], not: ["marked", "logged creatine"]),
                 category: .supplement, description: "Skipped = did NOT take", isTrainSet: false),
    ]

    // MARK: - Navigation — 8 cases

    static let navigation: [HardCase] = [
        HardCase(input: "Take me to wieght", history: nil,
                 expectedTool: "navigate_to", expectedParamHints: ["screen": "weight"],
                 responseRubric: .contains("weight"), category: .navigation,
                 description: "Typo in screen name", isTrainSet: true),

        HardCase(input: "Bring up sleep stats", history: nil,
                 expectedTool: "navigate_to", expectedParamHints: ["screen": "bodyRhythm"],
                 responseRubric: .contains("sleep"), category: .navigation,
                 description: "Alternative name for sleep screen", isTrainSet: true),

        HardCase(input: "CGM tab", history: nil,
                 expectedTool: "navigate_to", expectedParamHints: ["screen": "glucose"],
                 responseRubric: .contains("glucose"), category: .navigation,
                 description: "Medical acronym for glucose monitor", isTrainSet: true),

        HardCase(input: "Show me my macros", history: nil,
                 expectedTool: "navigate_to", expectedParamHints: ["screen": "food"],
                 responseRubric: .any, category: .navigation,
                 description: "'Macros' → food tab", isTrainSet: true),

        HardCase(input: "open the gym section", history: nil,
                 expectedTool: "navigate_to", expectedParamHints: ["screen": "exercise"],
                 responseRubric: .contains("exercise"), category: .navigation,
                 description: "'Gym section' = exercise screen", isTrainSet: true),

        HardCase(input: "go to labs", history: nil,
                 expectedTool: "navigate_to", expectedParamHints: ["screen": "biomarkers"],
                 responseRubric: .contains("biomarker"), category: .navigation,
                 description: "'Labs' = biomarkers screen", isTrainSet: true),

        // Held-out
        HardCase(input: "Switch to the food dairy", history: nil,
                 expectedTool: "navigate_to", expectedParamHints: ["screen": "food"],
                 responseRubric: .any, category: .navigation,
                 description: "Typo 'dairy' vs 'diary'", isTrainSet: false),

        HardCase(input: "body fat screen", history: nil,
                 expectedTool: "navigate_to", expectedParamHints: ["screen": "bodyComposition"],
                 responseRubric: .any, category: .navigation,
                 description: "Body fat = body composition screen", isTrainSet: false),
    ]

    // MARK: - Context Switch (topic change mid-conversation) — 5 cases

    static let contextSwitch: [HardCase] = [
        HardCase(input: "actually how did I sleep?",
                 history: "User: log 2 eggs\nAssistant: Logged 2 eggs (240 cal).",
                 expectedTool: "sleep_recovery", expectedParamHints: [:],
                 responseRubric: .contains("sleep"), category: .contextSwitch,
                 description: "Topic switch from food to sleep", isTrainSet: true),

        HardCase(input: "wait what's my weight this week?",
                 history: "User: did I take vitamin D\nAssistant: Yes, vitamin D marked today.",
                 expectedTool: "weight_info", expectedParamHints: [:],
                 responseRubric: .contains("kg", "weight"), category: .contextSwitch,
                 description: "Topic switch from supplement to weight", isTrainSet: true),

        HardCase(input: "never mind, just show my calories",
                 history: "User: what's my weight trend\nAssistant: Down 0.3kg/week over last month.",
                 expectedTool: "food_info", expectedParamHints: [:],
                 responseRubric: .contains("cal"), category: .contextSwitch,
                 description: "Redirect from weight to food", isTrainSet: true),

        // Held-out
        HardCase(input: "by the way how are my supplements?",
                 history: "User: calories left\nAssistant: 930 calories remaining today.",
                 expectedTool: "supplements", expectedParamHints: [:],
                 responseRubric: .any, category: .contextSwitch,
                 description: "Side topic switch from food to supplements", isTrainSet: false),

        HardCase(input: "random question — how was my hrv last night?",
                 history: "User: log biryani\nAssistant: Logged biryani. ~550 cal.",
                 expectedTool: "sleep_recovery", expectedParamHints: [:],
                 responseRubric: .contains("hrv", "sleep"), category: .contextSwitch,
                 description: "Explicit 'random question' prefix before topic switch", isTrainSet: false),
    ]

    // MARK: - Quick Reply Pills (regression guard) — 7 cases

    static let quickReplyPills: [HardCase] = [
        HardCase(input: "daily summary", history: nil,
                 expectedTool: "food_info", expectedParamHints: [:],
                 responseRubric: .contains("cal"), category: .quickReplyPills,
                 description: "Quick reply pill: daily summary", isTrainSet: true),

        HardCase(input: "calories left", history: nil,
                 expectedTool: "food_info", expectedParamHints: [:],
                 responseRubric: .contains("cal"), category: .quickReplyPills,
                 description: "Quick reply pill: calories remaining", isTrainSet: true),

        HardCase(input: "how am I doing", history: nil,
                 expectedTool: "food_info", expectedParamHints: [:],
                 responseRubric: .contains("cal"), category: .quickReplyPills,
                 description: "Quick reply pill: daily status", isTrainSet: true),

        HardCase(input: "weight trend", history: nil,
                 expectedTool: "weight_info", expectedParamHints: [:],
                 responseRubric: .contains("kg", "weight", "trend"), category: .quickReplyPills,
                 description: "Quick reply pill: weight trend", isTrainSet: true),

        HardCase(input: "did I take my vitamins", history: nil,
                 expectedTool: "supplements", expectedParamHints: [:],
                 responseRubric: .any, category: .quickReplyPills,
                 description: "Quick reply pill: supplement status", isTrainSet: true),

        HardCase(input: "how did I sleep", history: nil,
                 expectedTool: "sleep_recovery", expectedParamHints: [:],
                 responseRubric: .contains("sleep", "h"), category: .quickReplyPills,
                 description: "Quick reply pill: sleep check", isTrainSet: true),

        HardCase(input: "weekly summary", history: nil,
                 expectedTool: "food_info", expectedParamHints: [:],
                 responseRubric: .contains("cal", "week"), category: .quickReplyPills,
                 description: "Quick reply pill: weekly food summary", isTrainSet: true),
    ]
}

// MARK: - Validation

extension HardEvalSet {
    static let validTools: Set<String> = [
        "log_food", "food_info", "log_weight", "weight_info", "start_workout",
        "log_activity", "exercise_info", "sleep_recovery", "mark_supplement",
        "supplements", "set_goal", "delete_food", "body_comp", "glucose",
        "biomarkers", "navigate_to", "chat"
    ]

    static func validate() -> [String] {
        var errors: [String] = []
        let trainCount = all.filter(\.isTrainSet).count
        let heldCount = all.filter { !$0.isTrainSet }.count
        if trainCount + heldCount != all.count { errors.append("Count mismatch") }
        for c in all {
            if !validTools.contains(c.expectedTool) {
                errors.append("Invalid tool '\(c.expectedTool)' in: \(c.description)")
            }
        }
        return errors
    }
}
