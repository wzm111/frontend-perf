#!/bin/bash
# Configuration Loader / 配置文件加载器
# 解析 .frontend-perf.yml 配置文件，输出 shell 可 eval 的变量定义
# Usage: eval "$(bash config-loader.sh [config_file])"
#
# Supported config format (simple key-value / nested with dots):
#   thresholds:
#     maxBundleSize: 500000
#     maxImageSize: 102400
#     lcpThreshold: 2500
#     clsThreshold: 0.1
#   rules:
#     ignore:
#       - src/legacy/**
#       - test/**
#     customReplacements:
#       - from: old-lib
#         to: new-lib

CONFIG_FILE="${1:-.frontend-perf.yml}"

# Default values
THRESHOLD_MAX_BUNDLE_SIZE=500000
THRESHOLD_MAX_IMAGE_SIZE=102400
THRESHOLD_MAX_VIDEO_SIZE=5242880
THRESHOLD_MAX_CSS_SIZE=102400
THRESHOLD_LCP=2500
THRESHOLD_CLS=0.1
THRESHOLD_INP=200
THRESHOLD_TTFB=600

RULES_IGNORE=""
RULES_CUSTOM_REPLACEMENTS=""

# Parse YAML using node (preferred)
if command -v node &>/dev/null; then
  node -e "
    const fs = require('fs');
    const file = '$CONFIG_FILE';
    if (!fs.existsSync(file)) {
      console.log('# No config file found, using defaults');
      process.exit(0);
    }

    const content = fs.readFileSync(file, 'utf8');

    // Simple YAML parser for flat/nested config
    const lines = content.split('\n');
    let currentSection = '';
    let inList = false;
    let listBuffer = '';
    let indentStack = [];

    const output = [];
    output.push('# Parsed from ' + file);

    function unindent(line) {
      const match = line.match(/^(\s*)/);
      return match ? match[1].length : 0;
    }

    function parseValue(val) {
      val = val.trim();
      if (val === 'true') return 'true';
      if (val === 'false') return 'false';
      if (val === 'null') return '';
      if (/^\d+$/.test(val)) return val;
      if (/^\d+\.\d+$/.test(val)) return val;
      return '\"' + val + '\"';
    }

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (!line.trim() || line.trim().startsWith('#')) continue;

      const indent = unindent(line);
      const trimmed = line.trim();

      if (trimmed.includes(':')) {
        const [key, ...rest] = trimmed.split(':');
        const val = rest.join(':').trim();

        if (indent === 0) {
          currentSection = key.trim();
          inList = false;
          listBuffer = '';

          if (val) {
            output.push('CONFIG_' + currentSection.toUpperCase() + '=' + parseValue(val));
          }
        } else if (indent === 2 && currentSection) {
          const fullKey = currentSection + '_' + key.trim();

          if (!val && !trimmed.endsWith(':')) {
            // Could be empty value
            output.push('CONFIG_' + fullKey.toUpperCase() + '=\"\"');
          } else if (val) {
            output.push('CONFIG_' + fullKey.toUpperCase() + '=' + parseValue(val));
          } else {
            // Nested section starting
            inList = true;
            listBuffer = fullKey;
          }
        } else if (indent >= 4 && inList && listBuffer) {
          // List item under a section
          if (trimmed.startsWith('- ')) {
            const itemVal = trimmed.substring(2).trim();
            output.push('CONFIG_' + listBuffer.toUpperCase() + '+=' + parseValue(itemVal) + ' ');
          } else {
            // Key-value under list item (complex)
            const [k, ...v] = trimmed.split(':');
            const kv = k.trim() + '=' + (v.join(':').trim() || '');
            output.push('CONFIG_' + listBuffer.toUpperCase() + '_ITEM+=' + kv + '|');
          }
        }
      }
    }

    // Map known threshold keys
    const thresholdMap = {
      'CONFIG_THRESHOLDS_MAXBUNDLESIZE': 'THRESHOLD_MAX_BUNDLE_SIZE',
      'CONFIG_THRESHOLDS_MAXIMAGESIZE': 'THRESHOLD_MAX_IMAGE_SIZE',
      'CONFIG_THRESHOLDS_MAXVIDEOSIZE': 'THRESHOLD_MAX_VIDEO_SIZE',
      'CONFIG_THRESHOLDS_MAXCSSSIZE': 'THRESHOLD_MAX_CSS_SIZE',
      'CONFIG_THRESHOLDS_LCP': 'THRESHOLD_LCP',
      'CONFIG_THRESHOLDS_CLS': 'THRESHOLD_CLS',
      'CONFIG_THRESHOLDS_INP': 'THRESHOLD_INP',
      'CONFIG_THRESHOLDS_TTFB': 'THRESHOLD_TTFB',
    };

    // Print mapped variables
    output.forEach(line => {
      if (line.startsWith('#')) {
        console.log(line);
        return;
      }
      const eqIdx = line.indexOf('=');
      if (eqIdx === -1) return;
      const key = line.substring(0, eqIdx);
      const val = line.substring(eqIdx + 1);

      if (thresholdMap[key]) {
        console.log(thresholdMap[key] + '=' + val);
      } else if (key.includes('IGNORE')) {
        console.log('RULES_IGNORE=\"' + val.replace(/^["\']|["\']$/g, '').trim() + '\"');
      } else {
        console.log(line);
      }
    });
  " 2>/dev/null
fi
