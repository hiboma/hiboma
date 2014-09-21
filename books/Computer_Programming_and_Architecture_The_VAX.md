# Computer_Programming_and_Architecture_The_VAX.txt

 * `zero-address instructions` ... stack マシン

    PUSH A
    PUSH B
    # スタックのトップの値を ADD する
    ADD
    POP  C    

 * `one-address instructions` ... accumlator machine, load and store マシン

    # accumlator が暗黙的に操作される
    LOAD  A      # accumlator = A
    ADD   B      # accumlator = accumlator + B
    STORE C      # C = accumlator

 * `two-address instructions` ... register machine, RISC

    ADD A, B     # B = A + B

 * `three-address instructions` ... register machine
 
    ADD A, B, C  # C = A + B
    
## 2. PMS notation

システムの物理構造をテキスト化
分かりやすいのか分かりにくいのか いささか微妙な抽象化感

 * P processors
 * M memories
 * S switches
 * L links
 * T transducers
 * K contorllers
  * http://research.microsoft.com/en-us/um/people/gbell/cgb%20files/pms%20and%20isp%20notation%20to%20describe%20com%20structures%207303%20c.pdf

* Floating Point Numbers

    ±0.n x 2 ** ± m

 * n .. Exponent 指数
 * m .. Fraction 基数
