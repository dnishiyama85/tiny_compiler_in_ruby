require 'pp'
require 'pry'

class MySyntaxError < StandardError; end

# 予約語
@reserved = [
  'if', 'else', 'while', 'function', 'return'
]

# token struct
Token = Struct.new(:kind, :value)

# AST node struct
AST = Struct.new(:kind, :value, :children)

# token kinds
def space?(c)
  c =~ /\s/
end

def number?(c)
  c =~ /[0-9]/
end

def alpha?(c)
  c =~ /[a-zA-Z]/
end

def read_next_token(fp)
  c = nil
  # 空白読み飛ばし
  loop do
    c = fp.getc
    break unless space?(c)
  end
  return Token.new(:eof, nil) if fp.eof?

  # 二項演算子・記号読み取り
  case c
  when '+'
    return Token.new(:plus_op, nil)
  when '-'
    return Token.new(:minus_op, nil)
  when '*'
    return Token.new(:mul_op, nil)
  when '/'
    return Token.new(:div_op, nil)
  when '%'
    return Token.new(:mod_op, nil)
  when '<'
    return Token.new(:lt_op, nil)
  when '>'
    return Token.new(:gt_op, nil)
  when '('
    return Token.new(:lparen, nil)
  when ')'
    return Token.new(:rparen, nil)
  when '{'
    return Token.new(:lbrace, nil)
  when '}'
    return Token.new(:rbrace, nil)
  when '='
    return Token.new(:equal, nil)
  when ';'
    return Token.new(:semi, nil)
  when ','
    return Token.new(:comma, nil)
  end

  # identifier 読み取り
  if alpha?(c)
    id = c
    loop do
      c = fp.getc
      break unless number?(c) || alpha?(c)
      id += c
    end
    fp.ungetc(c)
    # 予約語判定
    if @reserved.include?(id)
      return Token.new(id.to_sym, nil)
    end
    # 予約語ではなかったとき
    return Token.new(:id, id)
  end

  # 数値読み取り
  if number?(c)
    num = c.to_i
    loop do
      c = fp.getc
      break unless number?(c)
      num = num * 10 + c.to_i
    end
    fp.ungetc(c)
    return Token.new(:number, num)
  end
end

def tokenize(fp)
  tokens = []
  loop do
    tokens << read_next_token(fp)
    break if fp.eof?
  end
  tokens
end

def get_token
  @tokens.shift
end

def unget_token(t)
  @tokens.unshift(t)
end

def build_number
  token = get_token
  raise MySyntaxError, '数値でない' unless token.kind == :number
  AST.new(:number, token.value, [])
end

# <factor> → id | (<expression>)
def build_factor
  # 因子は直値, id または (式) の形
  token = get_token
  # 直値の場合
  return AST.new(:number, token.value, []) if token.kind == :number
  # id の場合
  if token.kind == :id
    # 関数呼び出しか？
    next_token = get_token
    if next_token.kind == :lparen
      # 関数呼び出し
      func_name = token.value
      rparen = get_token
      if rparen.kind == :rparen
        # 引数がない
        return AST.new(:call, token.value, [])
      else
        unget_token(rparen)
      end
      # 引数の処理
      args = []
      loop do
        args << build_expression
        token = get_token
        unless token.kind == :comma
          unget_token(token)
          break
        end
      end
      next_token = get_token
      raise MySyntaxError, '関数呼び出しの ) がない' unless next_token.kind == :rparen
      return AST.new(:call, func_name, args)
    else
      # 変数参照
      unget_token(next_token)
      return AST.new(:id, token.value, token.value)
    end
  end
  # (式) の場合
  if token.kind == :lparen
    e = build_expression
    # 閉じカッコを確認
    raise MySyntaxError, '閉じカッコがない' unless get_token.kind == :rparen
    return e
  end

  raise MySyntaxError, '因子は数値または開きカッコでなければならない'
end

# <term> → <factor> [[ * <factor> ]]
def build_term
  # 一因子め
  e = build_factor
  # 以降の因子を処理する
  loop do
    token = get_token
    unless [:mul_op, :div_op, :mod_op].include?(token.kind)
      # 1つ読みすぎたので戻しておく
      unget_token(token)
      return e
    end
    ee = AST.new(token.kind, nil, [])
    ee.children << e
    ee.children << build_factor
    e = ee
  end
end

# <expression> → <term> [[ + <term> ]] | <term> > <term> | <term> < <term>
def build_expression
  # 一項目
  e = build_term
  # 以降の項を処理する
  loop do
    token = get_token
    # 次が 比較演算子の場合
    if [:lt_op, :gt_op].include?(token.kind)
      ee = AST.new(token.kind, nil, [])
      ee.children << e # 左辺
      ee.children << build_expression # 右辺
      return ee
    end
    unless [:plus_op, :minus_op].include?(token.kind)
      # 読みすぎたのを戻す
      unget_token(token)
      return e
    end
    ee = AST.new(token.kind, nil, [])
    ee.children << e
    ee.children << build_term
    e = ee
  end
end

# 代入式
# <assignment_expression> -> id = E | ε
def build_assignment_expression
  token_id = get_token
  raise MySyntaxError, '代入式の左辺が変数でない' unless token_id.kind == :id
  token_assign = get_token
  raise MySyntaxError, "代入式に = がない: token = #{token_assign.kind}" unless token_assign.kind == :equal
  a = AST.new(:assignment, nil, [])
  a.children << AST.new(:id, token_id.value, [])
  a.children << build_expression
  a
end

# 代入文
# <assignment> → <assignment_expression>;
def build_assignment
  token = get_token
  # セミコロンだけで終わるやつ
  return AST.new(:none, nil, []) if token.kind == :semi
  # セミコロンだけじゃないやつ
  unget_token(token)
  a = build_assignment_expression
  token = get_token
  raise MySyntaxError, '代入文の最後にセミコロンがない' unless token.kind == :semi
  a
end

# if 文
# <if> → if (<expression>) <sentence>
#      | if (<expression>) <sentence> else <sentence>
def build_if
  token = get_token
  i = AST.new(:if, nil, [])
  raise MySyntaxError, 'if 文が if で始まっていない' unless token.kind == :if
  token = get_token
  raise MySyntaxError, 'if の後に ( がない' unless token.kind == :lparen
  i.children << build_expression
  token = get_token
  raise MySyntaxError, 'if の条件式の ) がない' unless token.kind == :rparen
  # if の statement 部分
  if_statement = AST.new(:if_statement, nil, [])
  if_statement.children << build_sentence
  # else があるか？
  token = get_token
  if token.kind == :else
    # ある
    if_statement.children << build_sentence
  else
    # トークン戻し
    unget_token(token)
  end
  i.children << if_statement
  i
end

# while 文
# <while> → while (<expression>) <sentence>
def build_while
  token = get_token
  w = AST.new(:while, nil, [])
  raise MySyntaxError, 'while 文が while で始まっていない' unless token.kind == :while
  token = get_token
  raise MySyntaxError, 'while の後に ( がない' unless token.kind == :lparen
  w.children << build_expression
  token = get_token
  raise MySyntaxError, 'while の条件式の ) がない' unless token.kind == :rparen
  w.children << build_sentence
  w
end

# 関数定義
# <function> → function id () <sentence>
def build_function_decl
  raise MySyntaxError, '関数を入れ子で定義している' unless @block_level.zero?
  @block_level += 1
  token = get_token
  raise MySyntaxError, '関数定義が function で始まっていない' unless token.kind == :function
  func_name = get_token
  raise MySyntaxError, '関数定義に関数名がない' unless func_name.kind == :id
  token = get_token
  raise MySyntaxError, '関数名のあとに ( がない' unless token.kind == :lparen
  # 仮引数の処理
  args = []
  loop do
    token = get_token
    unless token.kind == :id
      unget_token(token)
      break
    end
    args << AST.new(:id, token.value, [])
    token = get_token
    unless token.kind == :comma
      unget_token(token)
      break
    end
  end
  token = get_token
  raise MySyntaxError, '仮引数列挙のあとに ) がない' unless token.kind == :rparen
  f = AST.new(:function_decl, nil, [])
  f.value = func_name
  # 関数本体
  f.children << build_complex_sentence
  # 仮引数を格納
  f.children.concat(args)
  @block_level -= 1
  f
end

# リターン文
# <return> → return <expression> <semi>
def build_return
  raise MySyntaxError, 'リターン文が 関数の外にある' unless @block_level > 0
  token = get_token
  raise MySyntaxError, 'リターン文が return で始まっていない' unless token.kind == :return
  r = AST.new(:return, nil, [])
  r.children << build_expression
  # セミコロン確認
  token = get_token
  raise MySyntaxError, 'リターン文にセミコロンがない' unless token.kind == :semi
  r
end

# 複文
# <complex_sentence> → { <sentence> [[ <sentence> ]]}
def build_complex_sentence
  token = get_token
  raise MySyntaxError, '複文が { で始まっていない' unless token.kind == :lbrace
  # 複文ノード
  cs = AST.new(:complex_sentence, nil, [])
  # 1つ目の文
  cs.children << build_sentence
  # 以降の文
  loop do
    # 一つ先読み
    token = get_token
    unget_token(token)
    unless [:lbrace, :while, :if, :id, :return].include?(token.kind)
      break
    end
    cs.children << build_sentence
  end
  # 閉じカッコの確認
  token = get_token
  raise MySyntaxError, "複文が } で終わっていない: token = #{token.kind}" unless token.kind == :rbrace
  cs
end

# 文
# <sentence> → <complex_sentence> | <if> | <while>
#                                 | <assignment> | <function> | <return>
def build_sentence
  # 次のトークンを一つ先読みすれば次が何かがわかる
  token = get_token
  unget_token(token)
  if token.kind == :lbrace
    return build_complex_sentence
  elsif token.kind == :while
    return build_while
  elsif token.kind == :if
    return build_if
  elsif token.kind == :id || token.kind == :semi
    return build_assignment
  elsif token.kind == :function
    return build_function
  elsif token.kind == :return
    return build_return
  else
    raise MySyntaxError, "文の始まりが不正： token = #{token.kind}"
  end
end

# トップレベル
# <toplevel> → <element> [[ <element> ]]
# <element> → <id> | <function>
def build_toplevel
  top = AST.new(:toplevel, nil, [])
  loop do
    token = get_token
    unget_token(token)
    if token.kind == :id
      top.children << build_assignment
    elsif token.kind == :function
      top.children << build_function_decl
    elsif token.kind == :eof
      break
    else
      raise MySyntaxError, 'トップレベルに変数、関数宣言以外のものがある'
    end
  end
  top
end

def gen_code(sym, operand = nil)
  code = sym.to_s
  code += ' ' + operand.to_s unless operand.nil?
  code
end

@cnt = -1
@codes = []
@variables = {} # ローカル変数表
@arguments = {} # 関数の引数表
@functions = {} # 関数表
@block_level = 0
@current_function_name = ''
# 抽象構文木をスタックマシンのインストラクションにコンパイルする
def compile_ast(node)
  case node.kind
  when :plus_op
    compile_ast(node.children[1])
    compile_ast(node.children[0])
    @cnt += 1
    @codes[@cnt] = gen_code(:add)
  when :minus_op
    compile_ast(node.children[1])
    compile_ast(node.children[0])
    @cnt += 1
    @codes[@cnt] = gen_code(:sub)
  when :mul_op
    compile_ast(node.children[1])
    compile_ast(node.children[0])
    @cnt += 1
    @codes[@cnt] = gen_code(:mul)
  when :div_op
    compile_ast(node.children[1])
    compile_ast(node.children[0])
    @cnt += 1
    @codes[@cnt] = gen_code(:div)
  when :mod_op
    compile_ast(node.children[1])
    compile_ast(node.children[0])
    @cnt += 1
    @codes[@cnt] = gen_code(:mod)
  when :gt_op
    compile_ast(node.children[1])
    compile_ast(node.children[0])
    @cnt += 1
    @codes[@cnt] = gen_code(:gt)
  when :lt_op
    compile_ast(node.children[1])
    compile_ast(node.children[0])
    @cnt += 1
    @codes[@cnt] = gen_code(:lt)
  when :number
    @cnt += 1
    @codes[@cnt] = gen_code(:push, node.value)
  when :id
    # 今のところ変数読み出ししかないはず
    if @variables[@current_function_name].key?(node.value)
      var_addr = @variables[@current_function_name][node.value]
      @cnt += 1
      @codes[@cnt] = gen_code(:loadl, var_addr)
    elsif @arguments[@current_function_name].key?(node.value)
      var_addr = @arguments[@current_function_name][node.value]
      @cnt += 1
      @codes[@cnt] = gen_code(:loada, var_addr)
    else
      raise MySyntaxError, "宣言されていない変数： #{node.value}"
    end
  when :if
    compile_ast(node.children[0])
    @cnt += 1
    @codes[@cnt] = gen_code(:beq0, 0)
    addr = @cnt
    if_statement = node.children[1]
    compile_ast(if_statement.children[0]) # if 文本体
    jump_to = @cnt + 1
    @codes[addr] = gen_code(:beq0, jump_to)
    if if_statement.children.size > 1 # else文本体
      compile_ast(if_statement.children[1])
    end
  when :while
    cond_addr = @cnt + 1
    compile_ast(node.children[0])
    @cnt += 1
    @codes[@cnt] = gen_code(:beq0, 0) # 飛び先は文の本体をコンパイルしないとわからない
    back_patch_addr = @cnt
    compile_ast(node.children[1]) # while 文の本体
    @cnt += 1
    @codes[@cnt] = gen_code(:jmp, cond_addr) # 条件を再確認するために戻る
    jump_to = @cnt + 1
    @codes[back_patch_addr] = gen_code(:beq0, jump_to)
  when :assignment
    # 左辺の変数名
    var_name = node.children[0].value
    # 変数表にない場合、領域を新たに確保して変数表に登録
    # TODO: 関数の引数に代入する場合を考える
    unless @variables[@current_function_name].key?(var_name)
      @variables[@current_function_name][var_name] = @variables[@current_function_name].size
      @cnt += 1
      @codes[@cnt] = gen_code(:push, -1)
    end
    # 代入式の右辺を計算させる
    compile_ast(node.children[1])
    # 変数のアドレスに格納させる
    @cnt += 1
    @codes[@cnt] = gen_code(:storel, @variables[@current_function_name][var_name])
  when :function_decl
    # 関数名
    func_name = node.value.value
    @current_function_name = func_name
    @variables[@current_function_name] = {}
    @arguments[@current_function_name] = {}
    # すでに登録されている関数ならエラー
    raise MySyntaxError, "すでに定義済みの関数です：#{func_name}" if @functions.key?(func_name)
    # 関数表に登録
    @functions[func_name] = { addr: @cnt + 1, argc: node.children.size - 1 }
    # 引数の登録
    args = node.children.slice(1..-1) || []
    args.reverse.each { |arg| @arguments[@current_function_name][arg.value] = @arguments[@current_function_name].size }
    # 本体のコンパイル
    compile_ast(node.children.first)
  when :call
    func_name = node.value
    raise MySyntaxError, "引数の数が違う：#{func_name}" unless @functions[func_name][:argc] == node.children.size
    # 戻り値格納用領域を確保する
    @cnt += 1
    @codes[@cnt] = gen_code(:push, -1)
    # 戻り先アドレスを積む
    @cnt += 1
    caller_adr = @cnt
    @codes[@cnt] = gen_code(:ldpc, -1)
    # 引数領域の確保
    node.children.each { |arg| compile_ast(arg) }
    # 引数の個数をレジスタにメモする
    @cnt += 1
    @codes[@cnt] = gen_code(:push, node.children.size)
    @cnt += 1
    @codes[@cnt] = gen_code(:strargc)
    # ベースポインタを退避させる
    @cnt += 1
    @codes[@cnt] = gen_code(:ldbp)
    # いまのスタックポインタをベースポインタとする
    @cnt += 1
    @codes[@cnt] = gen_code(:ldsp)
    @cnt += 1
    @codes[@cnt] = gen_code(:strbp)
    # 関数本体の処理へジャンプする
    raise MySyntaxError, "未定義の関数です: #{func_name}" unless @functions.key?(func_name)
    @cnt += 1
    @codes[@cnt] = gen_code(:jmp, @functions[func_name][:addr])
    @codes[caller_adr] = gen_code(:ldpc, @cnt - caller_adr + 1) # バックパッチ
  when :return
    # 戻り値を計算してスタックトップに積む
    compile_ast(node.children[0])
    # :return 疑似命令
    @cnt += 1
    @codes[@cnt] = gen_code(:ret)
  when :complex_sentence
    node.children.each { |child| compile_ast(child) }
  when :toplevel
    # main() 関数から始める
    @cnt += 1
    @codes[@cnt] = gen_code(:push, 0)
    @cnt += 1
    jump_to_main = @cnt
    @codes[jump_to_main] = gen_code(:jmp, -1)
    node.children.each { |child| compile_ast(child) }
    # main のアドレスを後埋め
    @codes[jump_to_main] = gen_code(:jmp, @functions['main'][:addr])
  else
    raise MySyntaxError, "不明なノード#{node.kind}"
  end
  @codes
end

def main
  filename = ARGV[0]
  fp = File.open(filename)
  @tokens = tokenize(fp)
  fp.close
  tree = build_toplevel
  codes = compile_ast(tree)
  puts codes.join("\n")
  puts 'stack'
end

main
