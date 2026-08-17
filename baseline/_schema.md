# Baseline Catalog Item Schema（基线目录项结构约定）

本目录是「安全基线核查系统」的**单一事实来源**。收集脚本（collectors）与 Web 平台（server）都读取这里的 YAML，按固定 schema 解耦协作。

---

## 1. 文件顶层结构

```yaml
catalog:
  id: host_linux            # 文件名主体，作为 catalog 标识；全局唯一
  platform: linux           # linux / windows / cross
  version: "1.0.0"          # 语义化版本，item 变更时递增
  description: "Linux 主机安全基线"
  items:
    - <item>
```

- `platform` 决定该文件被哪个收集入口加载：`linux` → host_linux.py；`windows` → host_windows.ps1；`cross` → 两个入口都加载（item 用 `platforms` 字段区分段）。

---

## 2. item 字段

| 字段 | 必填 | 说明 |
|---|---|---|
| `id` | 是 | 全局唯一，建议 `前缀-序列`，如 `LIN-SSH-001`、`MYSQL-001`、`WIN-PWD-001` |
| `category` | 是 | 大类：`主机安全` / `数据库安全` / `中间件安全` / `容器安全` / `网络安全` |
| `subsystem` | 否 | 子类：`SSH` / `MySQL` / `Tomcat` 等，用于 UI 细分分组 |
| `name` | 是 | 核查项名称 |
| `severity` | 是 | `high` / `medium` / `low` / `info` |
| `check_type` | 是 | `auto` / `manual` |
| `method` | 是 | 检测方式声明（见 §3） |
| `remediation` | 是 | 不合规时的加固方案（文本） |
| `reference` | 否 | 依据，如 `等保2.0 8.1.4` / `CIS MySQL Benchmark` |
| `timeout` | 否 | 单条命令超时秒数，默认 30 |
| `platforms` | 否 | cross 文件中区分 linux/windows 段；其它文件省略 |

---

## 3. method 结构（按 `type` 分）

### 3.1 `shell`（执行 shell 命令）
```yaml
method:
  type: shell
  actual_cmd: "grep -Ri '^\\s*PermitRootLogin' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | tail -1"
```
引擎执行 `actual_cmd`，取 stdout 作为实际值参与判定。仅跑**只读**命令。

### 3.2 `powershell`（执行 PowerShell 命令）
```yaml
method:
  type: powershell
  actual_cmd: "(Get-ItemProperty 'HKLM:\\SOFTWARE\\...').MaxPasswordAge"
```

### 3.3 `config_file`（解析配置文件，无需账号）
```yaml
method:
  type: config_file
  path_catalog: mysql_conf      # 指向 collectors/configs/paths.yaml 中的路径变量（兼容多发行版）
  format: ini                   # ini / key_value / yaml / conf
  section: mysqld               # ini 的段名；key_value/yaml 省略
  key: local_infile             # 要读取的键
```
引擎按 `format` 解析文件，取 `section.key`（或顶层 key）作为实际值。文件不存在 → status=unknown。

### 3.4 `process`（检查进程）
```yaml
method:
  type: process
  name: mysqld
  # 可选 expect_user: mysql  （判定启动用户是否为指定用户）
```
返回 `running:user` 或 `not_running` 作为实际值；可结合 judge `equals`/`contains` 判定。

### 3.5 `port`（检查监听端口/绑定地址）
```yaml
method:
  type: port
  port: 3306
  # 可选 expect_bind: "127.0.0.1" 或 "non_zero"（非 0.0.0.0）
```
返回监听地址列表，如 `0.0.0.0:3306`；结合 judge 判定是否监听危险地址。

### 3.6 `manual`（人工核查，不执行命令）
```yaml
method:
  type: manual
  description: "登录控制节点，检查 etcd 启动参数是否包含 --cert-file/--key-file..."
```
无命令、无 judge；收集脚本输出 `status=manual, actual=null`，报告里单列「待人工核查」。

---

## 4. judge 结构（判定条件）

`judge.type` 取值与语义：

| type | 语义 | 示例 |
|---|---|---|
| `equals` | actual 等于 value → pass | `equals: "no"` |
| `not_equals` | actual 不等于 value → pass | `not_equals: "SHUTDOWN"` |
| `contains` | actual 包含 value → pass | `contains: "audit"` |
| `regex_present` | actual 匹配正则 → pass | `regex_present: "(?i)deny=5"` |
| `regex_absent` | actual 不含正则 → pass | `regex_absent: "(?i)PermitRootLogin\\s+yes"` |
| `numeric_leq` | actual(取数字) ≤ value → pass | `numeric_leq: 90` |
| `numeric_geq` | actual(取数字) ≥ value → pass | `numeric_geq: 8` |
| `file_perm_leq` | actual(八进制权限串) ≤ value → pass | `file_perm_leq: 644` |

- `treat_empty_as`：actual 为空时的兜底 `pass`/`fail`（**强烈建议配置**，避免「未设置=通过」误判）。
- `expected`：给报告展示的期望描述文本（可选，缺省由 judge 推导）。

---

## 5. 维护约定

1. 新增 item 必须保证 `id` 全局唯一；改 item 语义时递增 `catalog.version`。
2. 只写只读命令，禁止在 `actual_cmd` 里写 `>`/`rm`/`systemctl restart` 等副作用。
3. 命令来自 YAML，禁止拼接用户输入，杜绝命令注入。
4. 跨发行版路径差异统一抽到 `collectors/configs/paths.yaml`，item 只引用变量名。
5. 提交前运行 `python baseline/_validate.py` 校验所有 yaml 合法、id 唯一、judge.type 在白名单。
