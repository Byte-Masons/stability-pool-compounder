module.exports = {
  "ignorePatterns": ["lib/"],
  "env": {
    "commonjs": true,
    "es2021": true,
    "node": true,
  },
  "extends": "eslint:recommended",
  "parserOptions": {
    "ecmaVersion": "latest",
  },
  "rules": {
    "indent": [
      "error",
      2,
    ],
    "linebreak-style": [
      "error",
      "unix",
    ],
    "quotes": [
      "error",
      "double",
    ],
    "semi": [
      "error",
      "always",
    ],
    "comma-dangle": ["error", "always-multiline"],
    "max-len": ["error", {
      "code": 100,
      "ignoreUrls": true,
      "ignoreStrings": true,
    }],
    "eol-last": ["error", "always"],
  },
};
