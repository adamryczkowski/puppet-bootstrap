#!/usr/bin/ruby
print %x{/usr/bin/getent passwd}.class
%x{/usr/bin/getent passwd}.lines.each do |n|
	print n.chomp
end

