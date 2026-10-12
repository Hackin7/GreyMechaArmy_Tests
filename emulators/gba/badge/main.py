import sys
sys.path.insert(0, '/apps/gba')
from gba_app import app
from gba_menu import program_rom_app

if __name__ == '__main__':
    program_rom_app()
