# Revolve Tool for SketchUp
# Handles the interactive axis selection and geometry generation

module Dodo
  module Revolve
    class RevolveTool
      # Tool states
      STATE_PICK_AXIS_START = 0
      STATE_PICK_AXIS_END = 1
      STATE_PICK_ANGLE = 2

      # Default segments for revolve
      DEFAULT_SEGMENTS = 24

      # Tolerance for geometric comparisons
      TOLERANCE = 0.0001

      def initialize(profile_group)
        @profile_group = profile_group
        @state = STATE_PICK_AXIS_START
        @axis_start = nil
        @axis_end = nil
        @angle = 360.degrees
        @segments = DEFAULT_SEGMENTS
        @input_point = Sketchup::InputPoint.new
        @input_point2 = Sketchup::InputPoint.new
        @cursor_point = nil
      end

      def activate
        @state = STATE_PICK_AXIS_START
        update_status_text
        Sketchup.active_model.selection.clear
        Sketchup.active_model.selection.add(@profile_group)
      end

      def deactivate(view)
        view.invalidate
      end

      def resume(view)
        update_status_text
        view.invalidate
      end

      def suspend(view)
        view.invalidate
      end

      def onCancel(reason, view)
        Sketchup.active_model.select_tool(nil)
      end

      def onMouseMove(flags, x, y, view)
        case @state
        when STATE_PICK_AXIS_START
          @input_point.pick(view, x, y)
          @cursor_point = @input_point.position if @input_point.valid?
        when STATE_PICK_AXIS_END
          @input_point2.pick(view, x, y, @input_point)
          @cursor_point = @input_point2.position if @input_point2.valid?
        end
        view.invalidate
        view.tooltip = @input_point.tooltip if @input_point.valid?
      end

      def onLButtonDown(flags, x, y, view)
        case @state
        when STATE_PICK_AXIS_START
          if @input_point.valid?
            @axis_start = @input_point.position
            @state = STATE_PICK_AXIS_END
            update_status_text
          end
        when STATE_PICK_AXIS_END
          if @input_point2.valid?
            @axis_end = @input_point2.position
            if @axis_start.distance(@axis_end) > TOLERANCE
              perform_revolve(view)
              Sketchup.active_model.select_tool(nil)
            else
              UI.messagebox('Axis start and end points must be different.', MB_OK)
            end
          end
        end
        view.invalidate
      end

      def onUserText(text, view)
        # Allow user to enter number of segments or angle
        if text =~ /^(\d+)s$/i
          # Segments input (e.g., "36s")
          @segments = $1.to_i
          @segments = 3 if @segments < 3
          @segments = 360 if @segments > 360
          Sketchup.status_text = "Segments set to #{@segments}"
        elsif text =~ /^(\d+\.?\d*)$/
          # Angle input in degrees
          angle = $1.to_f.degrees
          if angle > 0 && angle <= 360.degrees
            @angle = angle
            Sketchup.status_text = "Angle set to #{@angle.radians}°"
          end
        end
      end

      def enableVCB?
        true
      end

      def draw(view)
        # Draw the axis line
        if @axis_start
          draw_point(view, @axis_start, 'green')

          if @state == STATE_PICK_AXIS_END && @cursor_point
            # Draw axis line preview
            view.line_width = 2
            view.drawing_color = 'red'
            view.draw_line(@axis_start, @cursor_point)
            draw_point(view, @cursor_point, 'red')

            # Draw axis direction indicator
            if @axis_start.distance(@cursor_point) > 0.1
              draw_axis_preview(view, @axis_start, @cursor_point)
            end
          end
        elsif @cursor_point
          draw_point(view, @cursor_point, 'green')
        end

        # Draw input point inference
        @input_point.draw(view) if @input_point.valid? && @state == STATE_PICK_AXIS_START
        @input_point2.draw(view) if @input_point2.valid? && @state == STATE_PICK_AXIS_END
      end

      def getExtents
        bb = Sketchup.active_model.bounds
        bb.add(@axis_start) if @axis_start
        bb.add(@cursor_point) if @cursor_point
        bb
      end

      private

      def draw_point(view, point, color)
        view.draw_points([point], 10, 2, color)
      end

      def draw_axis_preview(view, start_pt, end_pt)
        # Draw a small rotation preview arc
        axis_vector = end_pt - start_pt
        axis_vector.normalize!

        # Find perpendicular vector for preview
        perp = find_perpendicular_vector(axis_vector)

        # Draw small rotation arc indicator
        radius = @profile_group.bounds.diagonal / 4
        center = Geom::Point3d.linear_combination(0.5, start_pt, 0.5, end_pt)

        arc_points = []
        12.times do |i|
          angle = (i * 30).degrees
          tr = Geom::Transformation.rotation(center, axis_vector, angle)
          pt = center.offset(perp, radius)
          arc_points << pt.transform(tr)
        end

        view.drawing_color = 'blue'
        view.line_width = 1
        view.line_stipple = '-'
        (0...arc_points.length - 1).each do |i|
          view.draw_line(arc_points[i], arc_points[i + 1])
        end
      end

      def find_perpendicular_vector(vector)
        # Find a vector perpendicular to the given vector
        if vector.parallel?(Z_AXIS)
          return X_AXIS.clone
        else
          perp = vector.cross(Z_AXIS)
          perp.normalize!
          return perp
        end
      end

      def update_status_text
        case @state
        when STATE_PICK_AXIS_START
          Sketchup.status_text = 'Pick axis start point. Type segments (e.g., "36s") or angle (e.g., "180") in the VCB.'
          Sketchup.vcb_label = 'Segments/Angle:'
          Sketchup.vcb_value = "#{@segments}s / #{@angle.radians}°"
        when STATE_PICK_AXIS_END
          Sketchup.status_text = 'Pick axis end point (defines rotation direction by right-hand rule).'
          Sketchup.vcb_label = 'Segments/Angle:'
          Sketchup.vcb_value = "#{@segments}s / #{@angle.radians}°"
        end
      end

      def perform_revolve(view)
        model = Sketchup.active_model

        model.start_operation('Revolve', true)
        begin
          # Get the profile edges from the group
          profile_edges = collect_profile_edges(@profile_group)

          if profile_edges.empty?
            UI.messagebox('No edges found in the profile group.', MB_OK)
            model.abort_operation
            return
          end

          # Get profile points (ordered) - may return multiple chains
          profile_chains = collect_all_profile_chains(profile_edges)

          if profile_chains.empty? || profile_chains.all? { |chain| chain.length < 2 }
            UI.messagebox('Profile must have at least 2 connected points.', MB_OK)
            model.abort_operation
            return
          end

          # Create the revolved geometry
          axis_point = @axis_start
          axis_vector = @axis_end - @axis_start
          axis_vector.normalize!

          # Create polygon mesh for the revolved surface
          mesh = create_revolve_mesh(profile_chains, axis_point, axis_vector, @angle, @segments)

          if mesh.count_polygons == 0
            UI.messagebox('Could not create revolve geometry. Check that the profile is not on the axis.', MB_OK)
            model.abort_operation
            return
          end

          # Create a new group for the result
          result_group = model.active_entities.add_group
          result_group.entities.fill_from_mesh(mesh, true, Geom::PolygonMesh::AUTO_SOFTEN)

          # Copy materials if available
          copy_materials(@profile_group, result_group)

          # Optionally delete the original profile
          result = UI.messagebox('Delete the original profile group?', MB_YESNO)
          if result == IDYES
            @profile_group.erase!
          end

          model.commit_operation

          # Select the result
          model.selection.clear
          model.selection.add(result_group)

        rescue StandardError => e
          model.abort_operation
          UI.messagebox("Error during revolve: #{e.message}\n#{e.backtrace.first}", MB_OK)
        end
      end

      def collect_profile_edges(group)
        edges = []
        group.entities.each do |entity|
          if entity.is_a?(Sketchup::Edge)
            edges << entity
          elsif entity.is_a?(Sketchup::Face)
            entity.edges.each do |edge|
              edges << edge unless edges.include?(edge)
            end
          end
        end
        edges.uniq
      end

      # Collect all edge chains from the profile (handles multiple disconnected chains)
      def collect_all_profile_chains(edges)
        return [] if edges.empty?

        transform = @profile_group.transformation

        # Build adjacency map using a hash with point keys
        adjacency = Hash.new { |h, k| h[k] = [] }
        point_map = {} # Maps point_key to actual Point3d

        edges.each do |edge|
          p1 = edge.start.position.transform(transform)
          p2 = edge.end.position.transform(transform)
          k1 = point_key(p1)
          k2 = point_key(p2)

          adjacency[k1] << k2
          adjacency[k2] << k1
          point_map[k1] = p1
          point_map[k2] = p2
        end

        # Remove duplicate neighbors
        adjacency.each { |k, v| v.uniq! }

        chains = []
        visited_keys = Set.new

        # Process all unvisited vertices
        adjacency.keys.each do |start_key|
          next if visited_keys.include?(start_key)

          # Find endpoints (degree 1) to start from, or use this vertex for closed loops
          chain = trace_chain(start_key, adjacency, point_map, visited_keys)
          chains << chain if chain.length >= 2
        end

        chains
      end

      def trace_chain(start_key, adjacency, point_map, visited_keys)
        # If this vertex has degree 1, it's an endpoint - good start
        # If degree > 2, it's a junction - we'll handle multiple branches
        # If degree 2, it's part of a chain

        points = []
        current_key = start_key
        prev_key = nil

        # First, if we're not at an endpoint, try to find one by going backwards
        if adjacency[start_key].length == 2
          # Walk to find an endpoint
          temp_visited = Set.new
          while adjacency[current_key].length == 2 && !temp_visited.include?(current_key)
            temp_visited.add(current_key)
            neighbors = adjacency[current_key]
            next_key = neighbors.find { |n| n != prev_key }
            break unless next_key
            prev_key = current_key
            current_key = next_key
          end
          # Now current_key is either an endpoint or we've looped
          start_key = current_key
          prev_key = nil
        end

        # Now trace forward from start_key
        current_key = start_key
        prev_key = nil

        loop do
          break if visited_keys.include?(current_key) && points.length > 0

          visited_keys.add(current_key)
          points << point_map[current_key]

          neighbors = adjacency[current_key].reject { |n| n == prev_key }

          if neighbors.empty?
            break
          elsif neighbors.length == 1
            next_key = neighbors.first
            # Check if we've completed a loop
            if next_key == start_key && points.length > 2
              points << point_map[next_key] # Close the loop
              break
            elsif visited_keys.include?(next_key)
              break
            end
            prev_key = current_key
            current_key = next_key
          else
            # Junction - just take the first unvisited neighbor
            next_key = neighbors.find { |n| !visited_keys.include?(n) }
            break unless next_key
            prev_key = current_key
            current_key = next_key
          end
        end

        points
      end

      def point_key(point)
        # Create a string key for point lookup with appropriate precision
        precision = 4 # Reduced precision for better matching
        "#{point.x.round(precision)},#{point.y.round(precision)},#{point.z.round(precision)}"
      end

      def create_revolve_mesh(profile_chains, axis_point, axis_vector, angle, segments)
        # Calculate the number of rotation steps
        full_revolution = (angle - 360.degrees).abs < 0.001
        num_steps = full_revolution ? segments : segments + 1
        angle_step = angle / segments

        # Estimate total mesh size
        total_points = 0
        total_polygons = 0
        profile_chains.each do |chain|
          total_points += chain.length * num_steps
          total_polygons += (chain.length - 1) * segments * 2
        end

        mesh = Geom::PolygonMesh.new(total_points + 100, total_polygons + 100)

        # Process each chain
        profile_chains.each do |profile_points|
          next if profile_points.length < 2

          add_chain_to_mesh(mesh, profile_points, axis_point, axis_vector, angle, segments, full_revolution)
        end

        mesh
      end

      def add_chain_to_mesh(mesh, profile_points, axis_point, axis_vector, angle, segments, full_revolution)
        num_points = profile_points.length
        num_steps = full_revolution ? segments : segments + 1
        angle_step = angle / segments

        # Pre-calculate distances to axis for all profile points
        distances = profile_points.map { |pt| distance_to_axis(pt, axis_point, axis_vector) }

        # Determine winding order ONCE based on profile direction and rotation direction
        # Find a representative point on the profile that is not on the axis
        flip_winding = calculate_winding_order(profile_points, distances, axis_point, axis_vector, angle_step)

        # Generate rotated profile points
        rotated_profiles = []
        num_steps.times do |step|
          current_angle = step * angle_step
          rotation = Geom::Transformation.rotation(axis_point, axis_vector, current_angle)

          rotated_points = profile_points.map { |pt| pt.transform(rotation) }
          rotated_profiles << rotated_points
        end

        # Create quads between adjacent profiles
        segments.times do |step|
          next_step = (step + 1) % num_steps
          # For non-full revolution, don't wrap around
          next_step = step + 1 if !full_revolution && step == segments - 1
          next if next_step >= rotated_profiles.length

          profile_a = rotated_profiles[step]
          profile_b = rotated_profiles[next_step]

          (num_points - 1).times do |i|
            p1 = profile_a[i]
            p2 = profile_a[i + 1]
            p3 = profile_b[i + 1]
            p4 = profile_b[i]

            # Use pre-calculated distances
            dist1 = distances[i]
            dist2 = distances[i + 1]

            # Both points on axis - skip entirely (degenerate)
            if dist1 < TOLERANCE && dist2 < TOLERANCE
              next
            end

            # Point 1 (and 4) on axis - create single triangle
            if dist1 < TOLERANCE
              add_triangle_safe(mesh, p1, p2, p3, flip_winding)
              next
            end

            # Point 2 (and 3) on axis - create single triangle
            if dist2 < TOLERANCE
              add_triangle_safe(mesh, p1, p2, p4, flip_winding)
              next
            end

            # Normal case - create quad as two triangles
            add_triangle_safe(mesh, p1, p2, p3, flip_winding)
            add_triangle_safe(mesh, p1, p3, p4, flip_winding)
          end
        end

        # Add end caps if not a full revolution
        unless full_revolution
          is_closed = profile_points.first.distance(profile_points.last) < TOLERANCE
          if is_closed && profile_points.length >= 4
            add_profile_cap(mesh, rotated_profiles.first, axis_point, axis_vector, true)
            add_profile_cap(mesh, rotated_profiles.last, axis_point, axis_vector, false)
          end
        end
      end

      def calculate_winding_order(profile_points, distances, axis_point, axis_vector, angle_step)
        # Find a segment of the profile that is away from the axis
        ref_idx = nil
        distances.each_with_index do |dist, i|
          if dist > TOLERANCE && i + 1 < distances.length && distances[i + 1] > TOLERANCE
            ref_idx = i
            break
          end
        end

        # Fallback: just use first segment
        ref_idx ||= 0
        return false if ref_idx + 1 >= profile_points.length

        p1 = profile_points[ref_idx]
        p2 = profile_points[ref_idx + 1]

        # Find radial direction at the midpoint of this segment (from axis outward)
        midpoint = Geom::Point3d.linear_combination(0.5, p1, 0.5, p2)
        closest_on_axis = closest_point_on_axis(midpoint, axis_point, axis_vector)
        radial = midpoint - closest_on_axis

        # If midpoint is on axis, try p1 or p2
        if radial.length < TOLERANCE
          closest_on_axis = closest_point_on_axis(p1, axis_point, axis_vector)
          radial = p1 - closest_on_axis
        end
        if radial.length < TOLERANCE
          closest_on_axis = closest_point_on_axis(p2, axis_point, axis_vector)
          radial = p2 - closest_on_axis
          return false if radial.length < TOLERANCE
        end
        radial.normalize!

        # Calculate the actual normal from the triangle winding (p1, p2, p3)
        # where p3 is p2 rotated by one step
        rotation = Geom::Transformation.rotation(axis_point, axis_vector, angle_step)
        p3 = p2.transform(rotation)

        v1 = p2 - p1
        v2 = p3 - p1
        actual_normal = v1.cross(v2)
        return false if actual_normal.length < TOLERANCE
        actual_normal.normalize!

        # We want faces pointing OUTWARD (away from axis)
        # If actual normal points inward (negative dot with radial), flip winding
        dot = actual_normal.dot(radial)
        dot < 0
      end

      def add_triangle_safe(mesh, p1, p2, p3, flip_winding)
        # Check for degenerate triangle (collinear points or zero area)
        v1 = p2 - p1
        v2 = p3 - p1

        # Skip if any edge is too short
        return if v1.length < TOLERANCE || v2.length < TOLERANCE
        return if p2.distance(p3) < TOLERANCE

        # Check for collinearity using cross product
        cross = v1.cross(v2)
        return if cross.length < TOLERANCE

        # Use pre-calculated winding order
        if flip_winding
          mesh.add_polygon(p1, p3, p2)
        else
          mesh.add_polygon(p1, p2, p3)
        end
      end

      def closest_point_on_axis(point, axis_point, axis_vector)
        v = point - axis_point
        projection = v.dot(axis_vector)
        axis_point.offset(axis_vector, projection)
      end

      def distance_to_axis(point, axis_point, axis_vector)
        # Calculate perpendicular distance from point to axis line
        closest = closest_point_on_axis(point, axis_point, axis_vector)
        point.distance(closest)
      end

      def add_profile_cap(mesh, profile_points, axis_point, axis_vector, reverse)
        # Add a face for the profile end cap
        return if profile_points.length < 3

        # Filter out points that are on the axis
        valid_points = profile_points.select do |pt|
          distance_to_axis(pt, axis_point, axis_vector) > TOLERANCE
        end

        return if valid_points.length < 3

        # Use ear clipping or fan triangulation for the cap
        # Simple fan from centroid works for convex profiles
        centroid = Geom::Point3d.new(0, 0, 0)
        valid_points.each do |pt|
          centroid.x += pt.x
          centroid.y += pt.y
          centroid.z += pt.z
        end
        centroid.x /= valid_points.length
        centroid.y /= valid_points.length
        centroid.z /= valid_points.length

        (valid_points.length - 1).times do |i|
          p1 = valid_points[i]
          p2 = valid_points[i + 1]

          # Skip degenerate triangles
          next if centroid.distance(p1) < TOLERANCE
          next if centroid.distance(p2) < TOLERANCE
          next if p1.distance(p2) < TOLERANCE

          if reverse
            mesh.add_polygon(centroid, p1, p2)
          else
            mesh.add_polygon(centroid, p2, p1)
          end
        end

        # Close the cap if profile is closed
        if profile_points.first.distance(profile_points.last) < TOLERANCE && valid_points.length >= 3
          p1 = valid_points.last
          p2 = valid_points.first
          if centroid.distance(p1) >= TOLERANCE && centroid.distance(p2) >= TOLERANCE && p1.distance(p2) >= TOLERANCE
            if reverse
              mesh.add_polygon(centroid, p1, p2)
            else
              mesh.add_polygon(centroid, p2, p1)
            end
          end
        end
      end

      def copy_materials(source_group, target_group)
        # Copy material from source group to target
        if source_group.material
          target_group.material = source_group.material
        end

        # Copy material from faces in source to faces in target
        source_material = nil
        source_group.entities.each do |entity|
          if entity.is_a?(Sketchup::Face) && entity.material
            source_material = entity.material
            break
          end
        end

        if source_material
          target_group.entities.each do |entity|
            if entity.is_a?(Sketchup::Face)
              entity.material = source_material
            end
          end
        end
      end

    end
  end
end
