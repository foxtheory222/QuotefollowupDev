import sys
from pathlib import Path


HOST_ROOT = Path(__file__).resolve().parents[1] / "src" / "freight_parser_host"
if str(HOST_ROOT) not in sys.path:
    sys.path.insert(0, str(HOST_ROOT))

from qfu_freight_parser.core import *  # noqa: F401,F403

