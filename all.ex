defmodule Toyagent.Core.Memory.All do
  def get() do
    long_term_memory = Toyagent.Core.Memory.LongTerm.get()
    short_term_memory = Toyagent.Core.Memory.ShortTerm.get()

    long_term_memory ++ short_term_memory
  end
end
