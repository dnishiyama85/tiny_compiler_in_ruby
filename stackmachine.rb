require 'pp'
require 'pry'

# list of instructions
PUSH    = :push
ADD     = :add
SUB     = :sub
MUL     = :mul
DIV     = :div
MOD     = :mod
GT      = :gt      # stackの上２つをpopして比較し、>なら１、それ以外は0をpushする。
LT      = :lt      # stackの上２つをpopして比較し、<なら１、それ以外は0をpushする。
BEQ0    = :beq0    # stackからpopして、0だったら,ラベルLに分岐する。
LOADL   = :loadl   # n番目の局所変数をpushする
STOREL  = :storel  # stackのtopの値をn番目の局所変数に格納する
LOADA   = :loada   # n番目の引数をpushする
STOREA  = :storea  # stackのtopの値をn番目の引数に格納する
LDBP    = :ldbp    # ベースポインタの値をpushする
STRBP   = :strbp   # stackのtopの値をベースポインタに格納する
LDSP    = :ldsp    # スタックポインタの値をpushする
STRSP   = :strsp   # stackのtopの値をスタックポインタに格納する
LDPC    = :ldpc    # プログラムカウンタの値をpushする
STRPC   = :strpc   # stackのtopの値をプログラムカウンタに格納する
LDARGC  = :ldargc  # 引数の個数の値をpushする
STRARGC = :strargc # stackのtopの値を引数の個数レジスタに格納する
JMP     = :jmp     # ラベルLにジャンプする
LABEL   = :label   # ラベル（疑似命令）
CALL    = :call    # 関数呼び出し命令
RET     = :ret     # return 命令
PRINT   = :print
STACK   = :stack

@stack = []
# @local_vars = Array.new(100, 0)
@bin_operators = {
  ADD.to_s => '+',
  SUB.to_s => '-',
  MUL.to_s => '*',
  DIV.to_s => '/',
  MOD.to_s => '%'
}

def bin_op(op)
  arg1 = @stack.pop
  arg2 = @stack.pop
  val = arg1.send(op, arg2)
  @stack.push(val)
end

def read_codes
  codes = []
  while (line = gets)
    # read an instruction
    line = line.strip.split
    if line.length > 1
      instr, n = line
      n = n.to_i
    else
      instr = line[0]
      n = 0
    end
    codes << { instr: instr, n: n }
  end
  codes
end

@pc = 0 # プログラムカウンタ
@bp = 0 # ベースポインタ
@argc = 0 # 現在の関数の引数の個数

def debug(codes)
  code = codes[@pc]
  puts "pc = #{@pc}, bp = #{@bp}, argc = #{@argc}, code = #{code[:instr]}, #{code[:n]}"
  pp @stack
  puts "---------------------------------------------------------------"
end
def execute_codes(codes)
  @pc = 0
  while @pc < codes.size
    debug(codes)
    code = codes[@pc]
    @pc = execute_step(code, @pc)
  end
end

def execute_step(code, pc)
  instr = code[:instr]
  n = code[:n]

  pc_changed = false

  case instr

  when PUSH.to_s
    @stack.push(n)

  when PRINT.to_s
    puts @stack.pop

  when STACK.to_s
    pp @stack

  when GT.to_s
    a = @stack.pop
    b = @stack.pop
    gt = a > b ? 1 : 0
    @stack.push(gt)

  when LT.to_s
    a = @stack.pop
    b = @stack.pop
    lt = a < b ? 1 : 0
    @stack.push(lt)

  when BEQ0.to_s
    z = @stack.pop
    if z.zero?
      pc = n
      pc_changed = true
    end

  when LOADL.to_s
    v = @stack[@bp + n + 1]
    @stack.push(v)
  when STOREL.to_s
    v = @stack.pop
    @stack[@bp + n + 1] = v
  when LOADA.to_s
    v = @stack[@bp - n - 1]
    @stack.push(v)
  when STOREA.to_s
    v = @stack.pop
    @stack[@bp - n - 1] = v
  when LDBP.to_s
    @stack.push(@bp)
  when STRBP.to_s
    @bp = @stack.pop
  when LDSP.to_s
    @stack.push(@stack.size - 1)
  when STRSP.to_s
    v = @stack.pop
    @stack.slice!(0..v)
  when LDPC.to_s
    @stack.push(pc + n)
  when STRBP.to_s
    pc = @stack.pop
    pc_changed = true
  when LDARGC.to_s
    @stack.push(@argc)
  when STRARGC.to_s
    @argc = @stack.pop
  when JMP.to_s
    pc = n
    pc_changed = true

  when LABEL.to_s
    pc = pc

  when RET.to_s
    # @bp == 0 なら main関数の終了
    if @bp.zero?
      pc = pc
    else
      # スタックトップにある戻り値を戻り値格納用領域にコピーする
      v = @stack.pop
      @stack[@bp - @argc - 2] = v
      # プログラムカウンタを戻り先にセットする
      pc = @stack[@bp - @argc - 1]
      pc_changed = true
      # ベースポインタを復帰させる
      old_bp = @bp
      @bp = @stack[@bp]
      # 戻り値格納用領域がスタックトップになるようにフレームを開放する
      @stack = @stack.slice(0..(old_bp - @argc - 2))
    end
  when *[ADD, SUB, MUL, DIV, MOD].map(&:to_s)
    op = @bin_operators[instr]
    bin_op(op)
  else
    raise StandardError, "不明なインストラクション：#{instr}"
  end

  pc += 1 unless pc_changed
  pc
end

def main
  codes = read_codes
  execute_codes(codes)
end

main
