require 'matrix'

class Vector
  public :[]=
end

class Simplex
  DEFAULT_MAX_PIVOTS = 10_000

  class UnboundedProblem < StandardError
  end

  attr_accessor :max_pivots

  # c - coefficients of objective function; size: num_vars
  # a - inequality lhs coefficients;   2dim size: num_inequalities, num_vars
  # b - inequality rhs constants            size: num_inequalities
  def initialize(c, a, b)
    num_vars = c.size
    num_inequalities = b.size
    raise(ArgumentError, "a doesn't match b") unless a.size == num_inequalities
    raise(ArgumentError, "a doesn't match c") unless a.first.size == num_vars

    @max_pivots = DEFAULT_MAX_PIVOTS

    # Problem dimensions; these never change
    @num_non_slack_vars = num_vars
    @num_constraints    = num_inequalities
    @num_vars           = @num_non_slack_vars + @num_constraints

    # Set up initial matrix A and vectors b, c
    @c = Vector[*(c.map { |flt| -1 * flt } + Array.new(@num_constraints, 0))]
    @a = a.map.with_index { |ary, i|
      if ary.size != @num_non_slack_vars
        raise ArgumentError, "a is inconsistent"
      end
      constraints = Array.new(@num_constraints) { |ci| ci == i ? 1 : 0 }
      Vector[*(ary + constraints)]
    }
    @b = Vector.elements(b, true)

    # set initial solution: all non-slack variables = 0
    @basic_vars = (@num_non_slack_vars...@num_vars).to_a
    self.update_solution
  end

  # does not modify vector / matrix
  def update_solution
    @x = Array.new(@num_vars, 0)

    @basic_vars.each do |basic_var|
      idx = nil
      @num_constraints.times { |i|
        if @a[i][basic_var] == 1
          idx = i
          break
        end
      }
      raise "no idx found for basic_var #{basic_var} in a" unless idx
      @x[basic_var] = @b[idx]
    end
  end

  def solution
    self.solve
    self.current_solution
  end

  def solve
    count = 0
    while self.can_improve?
      count += 1
      raise "too many pivots: #{count}" unless count < @max_pivots
      self.pivot
    end
  end

  def current_solution
    @x[0...@num_non_slack_vars]
  end

  def can_improve?
    !self.entering_variable.nil?
  end

  # idx of @c's minimum negative value
  # nil when no improvement is possible
  #
  def entering_variable
    (0...@c.size).select { |i| @c[i] < 0 }.min_by { |i| @c[i] }
  end

  def pivot
    pivot_column = self.entering_variable or return nil
    pivot_row = self.pivot_row(pivot_column) or raise UnboundedProblem
    leaving_var = nil
    @a[pivot_row].each_with_index { |a, i|
      if a == 1 and @basic_vars.include?(i)
        leaving_var = i
        break
      end
    }

    @basic_vars.delete(leaving_var)
    @basic_vars.push(pivot_column)
    @basic_vars.sort!

    pivot_ratio = Rational(1, @a[pivot_row][pivot_column])

    # update pivot row
    @a[pivot_row] *= pivot_ratio
    @b[pivot_row] = pivot_ratio * @b[pivot_row]

    # update objective
    @c -= @c[pivot_column] * @a[pivot_row]

    # update A and B
    @num_constraints.times { |i|
      next if i == pivot_row
      r = @a[i][pivot_column]
      @a[i] -= r * @a[pivot_row]
      @b[i] -= r * @b[pivot_row]
    }

    self.update_solution
  end

  def pivot_row(column_ix)
    min_ratio = nil
    idx = nil
    @num_constraints.times { |i|
      a, b = @a[i][column_ix], @b[i]
      next if a == 0 or (b < 0) ^ (a < 0)
      ratio = Rational(b, a)
      idx, min_ratio = i, ratio if min_ratio.nil? or ratio <= min_ratio
    }
    idx
  end

  def formatted_tableau
    if self.can_improve?
      pivot_column = self.entering_variable
      pivot_row    = self.pivot_row(pivot_column)
    else
      pivot_row = nil
    end
    c = @c.to_a.map { |flt| "%2.3f" % flt }
    b = @b.to_a.map { |flt| "%2.3f" % flt }
    a = @a.to_a.map { |vec| vec.to_a.map { |flt| "%2.3f" % flt } }
    if pivot_row
      a[pivot_row][pivot_column] = "*" + a[pivot_row][pivot_column]
    end
    max = (c + b + a + ["1234567"]).flatten.map(&:size).max
    result = []
    result << c.map { |str| str.rjust(max, " ") }
    a.zip(b) do |arow, brow|
      result << (arow + [brow]).map { |val| val.rjust(max, " ") }
      result.last.insert(arow.length, "|")
    end
    lines = result.map { |ary| ary.join("  ") }
    max_line_length = lines.map(&:length).max
    lines.insert(1, "-"*max_line_length)
    lines.join("\n")
  end
end
