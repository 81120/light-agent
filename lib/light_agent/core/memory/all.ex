defmodule LightAgent.Core.Memory.All do
  def get() do
    long_term_memory = LightAgent.Core.Memory.LongTerm.get()
    short_term_memory = LightAgent.Core.Memory.ShortTerm.get()

    long_term_memory ++ short_term_memory
  end
end
