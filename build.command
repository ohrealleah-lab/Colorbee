#!/bin/bash
cd "$(dirname "$0")"

echo "===================================================="
echo "  Hey Cutie Bee, Welcome to the Colorbee Build Tool"
echo "===================================================="
echo ""
echo "  1) Build"
echo "  2) Build & Run"
echo "  3) Clean"
echo "  4) Clean & Build"
echo "  5) Run Tests"
echo "  6) Performance Check (opens Colorbee windows for a few seconds)"
echo ""
read -p "Choose an option (1-6): " choice

case $choice in
  1)
    echo ""
    make build
    ;;
  2)
    echo ""
    make run
    ;;
  3)
    echo ""
    make clean
    ;;
  4)
    echo ""
    make clean && make build
    ;;
  5)
    echo ""
    make test
    ;;
  6)
    echo ""
    make bench
    ;;
  *)
    echo "Invalid option."
    ;;
esac

echo ""
echo "Press any key to close..."
read -n 1
