cd /workspace/services/frontend
npm ci
npm run lint

cd /workspace
# Only frontend ESLint
pre-commit run eslint --all-files

# Only Prettier
pre-commit run prettier --all-files
