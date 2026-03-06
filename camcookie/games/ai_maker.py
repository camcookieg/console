from __future__ import annotations

import random
from datetime import datetime

ENGINES = ["retro2d", "early2000s", "hybrid360", "infinite_worlds", "guided_worlds"]
BIOMES = ["forest", "city", "desert", "space", "ocean", "volcanic"]


def generate_world_spec(prompt: str, engine: str | None = None) -> dict:
    selected_engine = engine if engine in ENGINES else random.choice(ENGINES)
    biome = random.choice(BIOMES)
    difficulty = random.choice(["easy", "normal", "hard"])

    return {
        "title": f"AI World: {prompt[:40]}",
        "prompt": prompt,
        "engine": selected_engine,
        "biome": biome,
        "difficulty": difficulty,
        "seed": random.randint(1000, 999999),
        "created_at": datetime.utcnow().isoformat(timespec="seconds") + "Z",
        "objectives": [
            "Explore the spawn area",
            "Collect 10 resources",
            "Reach checkpoint alpha",
        ],
    }
