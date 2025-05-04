import random
import argparse

# Prefixes and suffixes for corporate-sounding names
prefixes = [
    'tech', 'data', 'info', 'smart', 'cloud', 'core', 'prime', 'next', 'micro', 'macro',
    'global', 'fusion', 'vertex', 'inno', 'hyper', 'syn', 'terra', 'nova', 'orbit',
    'apex', 'ascend', 'summit', 'ridge', 'meadow', 'valley', 'harbor', 'prairie', 'canyon',
    'beach', 'sun', 'sky', 'breeze', 'mountain', 'autumn', 'willow', 'cedar', 'maple',
    'sage', 'pine', 'ash', 'brook', 'glade', 'flora', 'ember', 'crystal', 'aurora',
    'zenith', 'vista', 'element', 'momentum', 'clarity', 'horizon', 'legacy', 'foundation'
] + [
    'pulse', 'spark', 'neon', 'aether', 'cascade', 'drift', 'current', 'echo', 'quartz', 'silver',
    'golden', 'lunar', 'stellar', 'celestial', 'cosmic', 'serene', 'vivid', 'radiant', 'gleam', 'glimmer',
    'shimmer', 'twilight', 'dawn', 'dusk', 'wave', 'flow', 'motion', 'dream', 'quest', 'odyssey',
    'voyage', 'pathway', 'trail', 'garden', 'grove', 'orchard', 'field', 'harvest', 'sprout', 'seedling',
    'bloom', 'petal', 'fern', 'moss', 'bramble', 'thicket', 'wildflower', 'ivy', 'dew', 'rain',
    'mist', 'fog', 'snow', 'frost', 'ice', 'glacier', 'whisper', 'song', 'chant', 'lullaby',
    'murmur', 'hush', 'melody', 'harmony', 'symphony', 'rhythm', 'tempo', 'cadence', 'ballad', 'verse',
    'script', 'scroll', 'manuscript', 'letter', 'scribe', 'journal', 'log', 'record', 'memo', 'note',
    'beacon', 'flare', 'lantern', 'torch', 'lamp', 'sparkle', 'shine', 'beam', 'ray', 'glow',
    'prism', 'spectrum', 'mirage', 'illusion', 'vision', 'focus', 'lens', 'frame', 'snapshot', 'portrait',
    'canvas', 'mural', 'painting', 'sketch', 'draw', 'draft', 'outline', 'design', 'pattern', 'texture',
    'weave', 'fabric', 'thread', 'yarn', 'quilt', 'tapestry', 'seam', 'stitch', 'loom', 'cotton',
    'wool', 'linen', 'silk', 'velvet', 'satin', 'lace', 'amber', 'onyx', 'jade', 'pearl',
    'opal', 'topaz', 'ruby', 'emerald', 'sapphire', 'diamond', 'agate', 'granite', 'marble', 'sandstone',
    'clay', 'terra', 'soil', 'pebble', 'stone', 'boulder', 'ridge', 'peak', 'plateau', 'plain',
    'basin', 'delta', 'bay', 'lagoon', 'fjord', 'cove', 'reef', 'island', 'archipelago', 'peninsula',
    'shore', 'coast', 'cape', 'inlet', 'plume', 'gale', 'zephyr', 'gust', 'storm',
    'cloudburst', 'drizzle', 'monsoon', 'tempest', 'hurricane', 'cyclone', 'breeze', 'squall', 'rainfall', 'tide',
    'ebb', 'ripple', 'swell', 'surf', 'breakers', 'foam', 'waterfall', 'brook',
    'creek', 'stream', 'river', 'estuary', 'lake', 'pond', 'reservoir', 'spring', 'geyser', 'well',
    'cavern', 'cave', 'grotto', 'hollow', 'nook', 'crag', 'bluff', 'knoll', 'summit', 'pinnacle',
    'spire', 'escarpment', 'cliff', 'mesa', 'butte', 'outcrop', 'prairie', 'savanna',
    'meadow', 'heath', 'moor', 'steppe', 'tundra', 'desert', 'dune', 'oasis', 'glade',
    'copse', 'woodland', 'forest', 'jungle', 'rainforest', 'canopy', 'undergrowth', 'vine', 'flora',
    'fauna', 'beast', 'creature', 'wild', 'roam', 'wander', 'trek', 'expedition', 'journey', 'travel',
    'explore', 'venture', 'pioneer', 'scout', 'trailblazer', 'pathfinder', 'navigator', 'mariner', 'sailor', 'seafarer',
    'voyager', 'adventure', 'discovery', 'find', 'seek', 'search', 'pursuit', 'chase', 'mission',
    'visionary', 'dreamer', 'thinker', 'creator', 'innovator', 'builder', 'maker', 'crafter', 'artisan', 'smith',
    'carver', 'weaver', 'mason', 'forger', 'engineer', 'architect', 'designer', 'planner', 'strategist', 'developer',
    'inventor', 'founder', 'leader', 'mentor', 'guide', 'teacher', 'scholar', 'student', 'apprentice', 'learner',
    'seeker', 'curious', 'investigator', 'analyzer', 'observer', 'watcher', 'keeper', 'guardian', 'protector', 'warden',
    'shepherd', 'champion', 'hero', 'advocate', 'supporter', 'ally', 'friend', 'partner', 'companion', 'fellow',
    'comrade', 'colleague', 'peer', 'neighbor', 'citizen', 'villager', 'resident', 'traveler', 'wanderer', 'nomad',
    'settler', 'colonist', 'habitant', 'inhabitant', 'avenue', 'boulevard', 'street', 'lane',
    'road', 'highway', 'track', 'course', 'route', 'passage', 'corridor', 'gateway', 'bridge',
    'arch', 'tunnel', 'viaduct', 'overpass', 'underpass', 'causeway', 'esplanade', 'promenade', 'boardwalk', 'pier',
    'wharf', 'dock', 'jetty', 'quay', 'harbor', 'port', 'marina', 'shipyard', 'boatyard', 'anchorage',
    'moorings', 'berth', 'haven', 'refuge', 'sanctuary', 'asylum', 'shelter', 'safehouse', 'depot', 'terminal', 'hub',
    'junction', 'crossroad', 'fork', 'interchange', 'roundabout', 'plaza', 'square',
    'court', 'courtyard', 'park', 'greenhouse', 'arboretum', 'nursery', 'commons', 'lawn', 'yard',
    'pasture', 'ranch', 'farm', 'plantation', 'vineyard', 'homestead', 'estate', 'manor', 'chateau', 'villa',
    'cottage', 'cabin', 'lodge', 'inn', 'hostel', 'hotel', 'resort', 'retreat', 'sanctum', 'shrine',
    'temple', 'chapel', 'cathedral', 'basilica', 'monastery', 'abbey', 'convent', 'cloister', 'citadel',
    'fortress', 'castle', 'keep', 'tower', 'turret', 'battlement', 'parapet', 'barracks', 'armory', 'arsenal',
    'workshop', 'studio', 'atelier', 'lab', 'laboratory', 'observatory', 'forge', 'foundry', 'mill', 'factory',
    'plant', 'complex', 'facility', 'warehouse', 'storehouse', 'granary', 'silo', 'barn', 'shed', 'stable',
    'kennel', 'aviary', 'menagerie', 'aquarium', 'zoo', 'reserve', 'preserve', 'habitat', 'enclosure',
    'corral', 'pen', 'grassland', 'wetland', 'swamp', 'marsh', 'bog', 'fen',
    'bayou', 'mangrove', 'atoll', 'islet', 'cay', 'shoal', 'sandbar', 'spit', 'headland',
    'point', 'ledge', 'slope', 'hill', 'mound', 'mountain', 'crest', 'valley',
    'canyon', 'gorge', 'ravine', 'gulch', 'draw', 'depression', 'sinkhole', 'lowland', 'upland',
    'highland', 'terrain', 'landscape', 'scenery', 'vista', 'panorama', 'horizon', 'outlook', 'view', 'prospect'
]


suffixes = [
    'solutions', 'systems', 'group', 'corp', 'labs', 'network', 'partners', 'consulting',
    'ventures', 'holdings', 'services', 'dynamics', 'platform', 'analytics', 'technologies',
    'matrix', 'pulse', 'institute', 'collective', 'alliance', 'resources', 'innovations'
]

service_words = [
    'cdn', 'api', 'dev', 'internal', 'files', 'assets', 'media', 'staging', 'test',
    'static', 'resources', 'images', 'uploads', 'downloads', 'cache', 'gateway', 'content'
]

# Benign words (colors, animals, names, objects, advertising)
benign_words = (
    ['red', 'blue', 'green', 'yellow', 'silver', 'gold', 'orange', 'grey', 'white', 'black',
     'violet', 'indigo', 'amber', 'teal', 'coral'] +
    ['lion', 'eagle', 'wolf', 'falcon', 'tiger', 'bear', 'panther', 'hawk', 'whale',
     'rabbit', 'otter', 'owl', 'deer', 'swan', 'fox'] +
    ['alex', 'sam', 'jordan', 'casey', 'drew', 'taylor', 'morgan', 'riley', 'blake',
     'devon', 'skyler', 'quinn', 'avery', 'charlie'] +
    ['stone', 'river', 'forest', 'sky', 'ocean', 'summit', 'ridge', 'valley', 'harbor',
     'meadow', 'canyon', 'peak', 'prairie', 'beach', 'hill', 'grove'] +
    ['ad', 'ads', 'advertising', 'promotion', 'promotions', 'branding', 'sponsorship',
     'sponsorships', 'impressions', 'placement', 'placements', 'audience', 'reach',
     'creative', 'creatives', 'engagement', 'visibility', 'awareness', 'messaging',
     'copy', 'copywriting', 'spot', 'spots', 'inventory', 'media_buying', 'media_planning']
)

risky_words = {'silent', 'quiet', 'brave', 'ventures', 'prime', 'fox'}

safe_tlds = ['.com', '.net', '.org']
caution_tlds = ['.ai', '.cloud', '.io', '.co', '.app']
risky_tlds = tlds = [".art", ".autos", ".beauty", ".boats", ".bond", ".cam", ".cfd", ".click", ".cyou", ".digital", ".guru", ".homes", ".icu", ".ink", ".life", ".live", ".lol", ".makeup", ".mom", ".motorcycles", ".online", ".pics", ".quest", ".rest", ".sbs", ".shop", ".site", ".skin", ".store", ".tattoo", ".today", ".top", ".website", ".wiki", ".world", ".xyz", ".yachts", ".space", ".fun", ".monster", ".gay", ".hair"]


special_suffix = 'institute'

tld_mapping = {
    'consulting': '.org', 'management': '.org', 'ventures': '.com',
    'analytics': '.com', 'services': '.net', 'labs': '.com',
    'resources': '.net', 'institute': '.org', 'platform': '.net'
}


def random_numeric(min_len=1, max_len=2):
    """Generate a random numeric string."""
    return ''.join(random.choices('0123456789', k=random.randint(min_len, max_len)))


def select_tld(suffix, default_pool):
    """Select appropriate TLD based on suffix."""
    return tld_mapping.get(suffix, random.choice(default_pool))


def generate_domains(n=10, risk_level="safe", hardened=False):
    """Generate corporate-like domain names with optional hardened logic."""
    domains = []
    used_combinations = set()

    if risk_level in ["safe", "hardened"]: tld_pool = safe_tlds
    elif risk_level == "caution": tld_pool = caution_tlds + safe_tlds
    else: tld_pool = risky_tlds

    for _ in range(n):
        tries = 0
        while True:
            prefix = random.choice(prefixes)
            suffix = random.choice(suffixes)
            combo_key = f"{prefix}-{suffix}"

            if not hardened or combo_key not in used_combinations or tries > 10:
                used_combinations.add(combo_key)
                break
            tries += 1

        tld = select_tld(suffix, safe_tlds) if hardened else random.choice(tld_pool)

        if hardened and random.random() < 0.4:
            benign = random.choice(benign_words)

            if suffix in ['consulting', 'management'] and benign in risky_words:
                benign = random.choice([w for w in benign_words if w not in risky_words])

            if random.random() < 0.5:
                name = f"{benign}{prefix}{suffix}"
            else:
                name = f"{prefix}{benign}{suffix}"
        else:
            if risk_level == "risky":
                parts = [random.choice(service_words)]
                if random.random() < 0.6:
                    parts[0] += random_numeric(1, 2)

                parts.append(prefix)
                if random.random() < 0.5:
                    parts[-1] += random_numeric(1, 2)

                parts.append(suffix)
                if random.random() < 0.5:
                    parts[-1] += random_numeric(1, 2)

                name = '-'.join(parts)
            else:
                joiner = '-' if (random.random() < (0.5 if risk_level == "safe" else 0.7)) else ''
                name = f"{prefix}{joiner}{suffix}"

                if risk_level == "caution" and random.random() < 0.3:
                    name += random_numeric(1, 1)

        if hardened and random.random() < 0.02:
            name = f"{prefix}{special_suffix}"

        domains.append(f"{name}{tld}".lower())

    return domains


def main():
    parser = argparse.ArgumentParser(description="Generate realistic corporate domains.")
    parser.add_argument('-n', '--number', type=int, default=10, help='Number of domains to generate')
    parser.add_argument('-t', '--type', type=str, choices=['safe', 'caution', 'risky', 'hardened'], default='safe', help='Type of domains to generate')

    args = parser.parse_args()

    hardened = args.type == 'hardened'
    risk_level = 'safe' if hardened else args.type

    domains = generate_domains(n=args.number, risk_level=risk_level, hardened=hardened)

    for domain in domains:
        print(domain)


if __name__ == "__main__":
    main()
