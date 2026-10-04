"""Small, reversible edits that connect personal words to the official decoder."""

CHANGES = [
    (
        'local function build_lexicon_index(entries, character_ranks, high_freq_limit, whitelist)\n',
        'local function build_lexicon_index(entries, character_ranks, high_freq_limit, whitelist, official_entries)\n'
        '    -- tiger-addons: keep official character primary codes when adding words.\n'
        '    local official_first = {}\n'
        '    for _, entry in ipairs(official_entries or entries) do\n'
        '        if official_first[entry.code] == nil then\n'
        '            official_first[entry.code] = entry.word\n'
        '        end\n'
        '    end\n',
    ),
    (
        '                if texts and texts[1] == character then\n',
        '                if texts and (official_first[code] or texts[1]) == character then\n',
    ),
    (
        '    local index = build_lexicon_index(entries, character_ranks, limit, whitelist)\n',
        '    -- tiger-addons: load personal words separately and merge only in memory.\n'
        '    local user_content = read_data_file("custom_phrase.txt")\n'
        '    local official_entries = entries\n'
        '    if user_content and user_content ~= "" then\n'
        '        entries = require("tiger_user_codes").merge(entries, user_content)\n'
        '    end\n'
        '    local index = build_lexicon_index(entries, character_ranks, limit, whitelist, official_entries)\n',
    ),
    (
        '    lexicon_state.learning_rules = learning.hash((codes_content or "") .. "\\0" ..\n',
        '    lexicon_state.learning_rules = learning.hash((codes_content or "") ..\n'
        '        (user_content and user_content ~= "" and "\\0" .. user_content or "") .. "\\0" ..\n',
    ),
]


def apply(source):
    """Plan every edit before writing; reject unknown or ambiguous source layouts."""
    for original, patched in CHANGES:
        if source.count(patched) == 1:
            continue
        if source.count(patched) or source.count(original) != 1:
            raise ValueError("Unsupported Tiger Sentence core; personal-word patch was not applied")
        source = source.replace(original, patched, 1)
    return source


def restore(source):
    """Remove only the exact managed edits, preserving any other upstream changes."""
    for original, patched in reversed(CHANGES):
        if source.count(patched) == 1:
            source = source.replace(patched, original, 1)
    return source
